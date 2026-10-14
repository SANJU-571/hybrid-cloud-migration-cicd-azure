import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cost_report  # noqa: E402

# Shape of a Cost Management Query API response (columns + rows).
DAILY = {
    "properties": {
        "columns": [
            {"name": "Cost", "type": "Number"},
            {"name": "UsageDate", "type": "Number"},
            {"name": "ServiceName", "type": "String"},
            {"name": "Currency", "type": "String"},
        ],
        "rows": [
            [6.0, 20261001, "Application Gateway", "USD"],
            [2.0, 20261001, "Virtual Machines", "USD"],
            [6.0, 20261002, "Application Gateway", "USD"],
            [1.0, 20261002, "Storage", "USD"],
        ],
    }
}

TAGS = {
    "properties": {
        "columns": [
            {"name": "Cost", "type": "Number"},
            {"name": "TagKey", "type": "String"},
            {"name": "TagValue", "type": "String"},
            {"name": "Currency", "type": "String"},
        ],
        "rows": [[14.0, "cost_center", "nfb-cloud-lab", "USD"], [1.0, "cost_center", None, "USD"]],
    }
}


def test_rows_as_dicts_maps_columns():
    rows = cost_report.rows_as_dicts(DAILY)
    assert rows[0] == {"Cost": 6.0, "UsageDate": 20261001, "ServiceName": "Application Gateway", "Currency": "USD"}


def test_summary_totals_forecast_and_ranking():
    s = cost_report.summarise(cost_report.rows_as_dicts(DAILY), budget=150, today=date(2026, 10, 2))
    assert s.month_to_date == 15.0
    assert s.daily_run_rate == 7.5
    assert s.forecast == 7.5 * 31
    assert list(s.by_service)[0] == "Application Gateway"
    assert s.by_day == {"2026-10-01": 8.0, "2026-10-02": 7.0}
    assert s.status == "FORECAST OVER BUDGET"  # 232.5 > 150


def test_status_thresholds():
    rows = [{"Cost": 1.0, "UsageDate": 20261001, "ServiceName": "x", "Currency": "USD"}]
    assert cost_report.summarise(rows, 100, date(2026, 10, 1)).status == "OK"  # forecast 31
    assert cost_report.summarise(rows, 35, date(2026, 10, 1)).status == "WARNING"  # 31 >= 28
    assert cost_report.summarise(rows, 1, date(2026, 10, 1)).status == "OVER BUDGET"


def test_untagged_costs_are_visible():
    totals = cost_report.tag_totals(cost_report.rows_as_dicts(TAGS))
    assert totals == {"nfb-cloud-lab": 14.0, "(untagged)": 1.0}


def test_markdown_contains_key_sections():
    s = cost_report.summarise(cost_report.rows_as_dicts(DAILY), 150, date(2026, 10, 2))
    md = cost_report.render_markdown("nfb-lab", s, {"nfb-cloud-lab": 14.0}, {"Unattached managed disks": []})
    assert "FORECAST OVER BUDGET" in md
    assert "| Application Gateway | 12.00 | 80% |" in md
    assert "Unattached managed disks**: 0" in md
