#!/usr/bin/env python3
"""FinOps report for one environment of the hybrid cloud.

Pulls month-to-date actual cost from the Azure Cost Management Query API
(free) for the environment's resource groups, then reports:

  * month-to-date spend, daily run-rate and a linear month-end forecast
    compared with the Terraform budget (monthly_budget_usd)
  * cost by Azure service and by the `cost_center` tag (enforced by policy)
  * waste checks: unattached disks, unused public IPs, VMs stopped but still
    allocated (still billed)

Auth and HTTP go through the Azure CLI (`az login` locally, OIDC in GitHub
Actions), so there are no extra dependencies or secrets.

Usage:
  python3 finops/cost_report.py --prefix nfb-lab --budget 150 \
      [--markdown report.md] [--csv daily.csv] [--fail-on-forecast-over-budget]
"""

from __future__ import annotations

import argparse
import calendar
import csv
import json
import subprocess
import sys
import tempfile
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date

API_VERSION = "2023-11-01"
WARN_AT = 0.8  # forecast >= 80% of budget -> warning


# ---------------------------------------------------------------------------
# Azure CLI helpers
# ---------------------------------------------------------------------------
def az(*args: str) -> object:
    out = subprocess.run(["az", *args, "-o", "json"], check=True, capture_output=True, text=True)
    return json.loads(out.stdout or "null")


def cost_query(subscription_id: str, resource_groups: list[str], grouping: dict, daily: bool) -> dict:
    body = {
        "type": "ActualCost",
        "timeframe": "MonthToDate",
        "dataset": {
            "granularity": "Daily" if daily else "None",
            "aggregation": {"totalCost": {"name": "Cost", "function": "Sum"}},
            "grouping": [grouping],
            "filter": {
                "dimensions": {
                    "name": "ResourceGroupName",
                    "operator": "In",
                    "values": resource_groups,
                }
            },
        },
    }
    url = (
        f"https://management.azure.com/subscriptions/{subscription_id}"
        f"/providers/Microsoft.CostManagement/query?api-version={API_VERSION}"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(body, fh)
    return az("rest", "--method", "post", "--url", url, "--body", f"@{fh.name}")  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# Pure functions (unit-tested)
# ---------------------------------------------------------------------------
def rows_as_dicts(result: dict) -> list[dict]:
    """Cost Management returns columns + rows; turn them into dicts."""
    props = result.get("properties", result)
    names = [c["name"] for c in props["columns"]]
    return [dict(zip(names, row)) for row in props["rows"]]


@dataclass
class Summary:
    month_to_date: float
    days_elapsed: int
    days_in_month: int
    budget: float
    currency: str
    by_service: dict[str, float] = field(default_factory=dict)
    by_day: dict[str, float] = field(default_factory=dict)

    @property
    def daily_run_rate(self) -> float:
        return self.month_to_date / max(self.days_elapsed, 1)

    @property
    def forecast(self) -> float:
        return self.daily_run_rate * self.days_in_month

    @property
    def status(self) -> str:
        if self.month_to_date >= self.budget:
            return "OVER BUDGET"
        if self.forecast >= self.budget:
            return "FORECAST OVER BUDGET"
        if self.forecast >= WARN_AT * self.budget:
            return "WARNING"
        return "OK"


def summarise(daily_service_rows: list[dict], budget: float, today: date) -> Summary:
    by_service: dict[str, float] = defaultdict(float)
    by_day: dict[str, float] = defaultdict(float)
    currency = "USD"
    for row in daily_service_rows:
        cost = float(row.get("Cost") or row.get("PreTaxCost") or 0)
        by_service[row.get("ServiceName") or "unknown"] += cost
        day = str(row.get("UsageDate", ""))
        by_day[f"{day[:4]}-{day[4:6]}-{day[6:8]}" if len(day) == 8 else day] += cost
        currency = row.get("Currency", currency)
    return Summary(
        month_to_date=sum(by_service.values()),
        days_elapsed=today.day,
        days_in_month=calendar.monthrange(today.year, today.month)[1],
        budget=budget,
        currency=currency,
        by_service=dict(sorted(by_service.items(), key=lambda kv: kv[1], reverse=True)),
        by_day=dict(sorted(by_day.items())),
    )


def tag_totals(tag_rows: list[dict]) -> dict[str, float]:
    totals: dict[str, float] = defaultdict(float)
    for row in tag_rows:
        value = row.get("TagValue") or "(untagged)"
        totals[value] += float(row.get("Cost") or row.get("PreTaxCost") or 0)
    return dict(sorted(totals.items(), key=lambda kv: kv[1], reverse=True))


def render_markdown(prefix: str, s: Summary, tags: dict[str, float], waste: dict[str, list[str]]) -> str:
    c = s.currency
    icon = {"OK": "🟢", "WARNING": "🟡"}.get(s.status, "🔴")
    lines = [
        f"## FinOps report: `{prefix}` ({date.today():%B %Y})",
        "",
        "| Metric | Value |",
        "|---|---|",
        f"| Status | {icon} **{s.status}** |",
        f"| Month-to-date spend | {s.month_to_date:,.2f} {c} |",
        f"| Daily run-rate | {s.daily_run_rate:,.2f} {c} |",
        f"| Month-end forecast (linear) | {s.forecast:,.2f} {c} |",
        f"| Budget | {s.budget:,.2f} {c} ({100 * s.forecast / s.budget:.0f}% forecast) |",
        "",
        "### Cost by service",
        "",
        "| Service | MTD cost | Share |",
        "|---|---:|---:|",
    ]
    total = s.month_to_date or 1
    lines += [f"| {k} | {v:,.2f} | {100 * v / total:.0f}% |" for k, v in s.by_service.items()]
    lines += ["", "### Cost by `cost_center` tag", "", "| cost_center | MTD cost |", "|---|---:|"]
    lines += [f"| {k} | {v:,.2f} |" for k, v in tags.items()] or ["| (no data) | |"]
    lines += ["", "### Waste checks", ""]
    for check, items in waste.items():
        lines.append(f"- **{check}**: {len(items)}" + (f" ({', '.join(items)})" if items else ""))
    lines += [
        "",
        "_Tip: `make destroy PROFILE=<profile>` stops all spend; budgets alert at 50/80/100%._",
    ]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Waste checks
# ---------------------------------------------------------------------------
def waste_checks(resource_groups: list[str]) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {
        "Unattached managed disks": [],
        "Public IPs not attached to anything": [],
        "VMs stopped but still allocated (billed)": [],
    }
    for rg in resource_groups:
        for d in az("disk", "list", "-g", rg) or []:  # type: ignore[union-attr]
            if d.get("diskState") == "Unattached":
                found["Unattached managed disks"].append(d["name"])
        for ip in az("network", "public-ip", "list", "-g", rg) or []:  # type: ignore[union-attr]
            if not ip.get("ipConfiguration") and not ip.get("natGateway"):
                found["Public IPs not attached to anything"].append(ip["name"])
        for vm in az("vm", "list", "-d", "-g", rg) or []:  # type: ignore[union-attr]
            if vm.get("powerState") == "VM stopped":
                found["VMs stopped but still allocated (billed)"].append(vm["name"])
    return found


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--prefix", default="nfb-lab", help="environment name prefix, e.g. nfb-lab")
    ap.add_argument("--budget", type=float, default=150.0, help="monthly budget (monthly_budget_usd)")
    ap.add_argument("--markdown", help="write the report to this file as well as stdout")
    ap.add_argument("--csv", help="write daily cost by service to this CSV file")
    ap.add_argument("--fail-on-forecast-over-budget", action="store_true")
    args = ap.parse_args()

    subscription_id = az("account", "show")["id"]  # type: ignore[index]
    rgs = [f"rg-{args.prefix}-azure", f"rg-{args.prefix}-onprem-sim", f"rg-{args.prefix}-aks-nodes"]

    daily = rows_as_dicts(cost_query(subscription_id, rgs, {"type": "Dimension", "name": "ServiceName"}, daily=True))
    tags = rows_as_dicts(cost_query(subscription_id, rgs, {"type": "TagKey", "name": "cost_center"}, daily=False))
    summary = summarise(daily, args.budget, date.today())
    report = render_markdown(args.prefix, summary, tag_totals(tags), waste_checks(rgs[:2]))

    print(report)
    if args.markdown:
        with open(args.markdown, "w", encoding="utf-8") as fh:
            fh.write(report)
    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh)
            writer.writerow(["date", "service", "cost"])
            for row in daily:
                writer.writerow([row.get("UsageDate"), row.get("ServiceName"), row.get("Cost")])

    if args.fail_on_forecast_over_budget and summary.status in {"OVER BUDGET", "FORECAST OVER BUDGET"}:
        print(f"::error::{args.prefix}: {summary.status}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
