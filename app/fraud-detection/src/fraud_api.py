"""N-Financial Bank fraud-detection API.

A small, dependency-light HTTP service used by the customer portal (VM Scale
Set) and, when AKS is enabled, run as a container on Kubernetes.

Endpoints
  GET  /            service info (kept for the VM-era portal)
  GET  /check       sample risk check (the portal links to /api/fraud/check)
  POST /v1/score    score a transaction (JSON in, JSON out)
  GET  /healthz     liveness probe
  GET  /readyz      readiness probe
  GET  /metrics     Prometheus metrics (RED + business metrics)

Fault injection for game days / SLO alert testing (environment variables):
  FAULT_ERROR_RATE   0.0-1.0  share of /v1/score and /check requests that return HTTP 500
  FAULT_LATENCY_MS   int      extra latency added to those requests
"""

from __future__ import annotations

import json
import logging
import os
import random
import signal
import socket
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

SERVICE = "fraud-detection"
VERSION = os.environ.get("APP_VERSION", "dev")
HIGH_RISK_COUNTRIES = {"KP", "IR", "SY"}  # sample sanctions list for the demo
RISKY_MERCHANT_CATEGORIES = {"gambling", "crypto", "gift_cards", "wire_transfer"}

REQUESTS = Counter(
    "http_requests_total", "HTTP requests by route and status code.", ["method", "route", "code"]
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency by route.",
    ["route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.3, 0.5, 1.0, 2.5),
)
DECISIONS = Counter("fraud_decisions_total", "Scoring decisions by outcome.", ["decision"])

logging.basicConfig(stream=sys.stdout, level=logging.INFO, format="%(message)s")
log = logging.getLogger(SERVICE)


class ValidationError(ValueError):
    """Raised when a scoring request is malformed."""


def score_transaction(txn: dict) -> dict:
    """Rule-based, explainable risk score in [0, 1].

    Deliberately simple and deterministic so it can be unit-tested and
    explained in an audit. A real model would sit behind the same contract.
    """
    if not isinstance(txn, dict):
        raise ValidationError("body must be a JSON object")
    try:
        amount = float(txn["amount"])
    except (KeyError, TypeError, ValueError) as exc:
        raise ValidationError("'amount' is required and must be a number") from exc
    if amount < 0:
        raise ValidationError("'amount' must be >= 0")

    country = str(txn.get("country", "CA")).upper()
    category = str(txn.get("merchant_category", "retail")).lower()
    card_present = bool(txn.get("card_present", True))
    hour = int(txn.get("hour", 12))
    if not 0 <= hour <= 23:
        raise ValidationError("'hour' must be 0-23")

    score, reasons = 0.05, []
    if amount >= 10_000:
        score += 0.45
        reasons.append("amount >= 10,000 (FINTRAC large-transaction threshold)")
    elif amount >= 2_000:
        score += 0.2
        reasons.append("amount >= 2,000")
    if country in HIGH_RISK_COUNTRIES:
        score += 0.5
        reasons.append(f"high-risk country {country}")
    elif country != "CA":
        score += 0.1
        reasons.append("cross-border transaction")
    if category in RISKY_MERCHANT_CATEGORIES:
        score += 0.2
        reasons.append(f"risky merchant category '{category}'")
    if not card_present:
        score += 0.1
        reasons.append("card not present")
    if hour < 5:
        score += 0.1
        reasons.append("unusual hour")

    score = round(min(score, 1.0), 3)
    decision = "decline" if score >= 0.8 else "review" if score >= 0.5 else "approve"
    return {"risk_score": score, "decision": decision, "reasons": reasons}


class Handler(BaseHTTPRequestHandler):
    server_version = f"{SERVICE}/{VERSION}"

    # ---- helpers -------------------------------------------------------
    def _send(self, code: int, body: dict | bytes, content_type: str = "application/json") -> None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        self._code = code

    def _faults(self) -> bool:
        """Apply injected latency/errors. Returns True if an error was sent."""
        latency_ms = int(os.environ.get("FAULT_LATENCY_MS", "0") or 0)
        if latency_ms > 0:
            time.sleep(latency_ms / 1000)
        error_rate = float(os.environ.get("FAULT_ERROR_RATE", "0") or 0)
        if error_rate > 0 and random.random() < error_rate:
            self._send(500, {"error": "injected fault"})
            return True
        return False

    def _route(self) -> str:
        path = self.path.split("?", 1)[0]
        known = {"/", "/check", "/v1/score", "/healthz", "/readyz", "/metrics"}
        return path if path in known else "other"

    def _observe(self, route: str, started: float) -> None:
        code = getattr(self, "_code", 500)
        REQUESTS.labels(self.command, route, str(code)).inc()
        LATENCY.labels(route).observe(time.perf_counter() - started)
        if route not in {"/healthz", "/readyz", "/metrics"}:
            log.info(
                json.dumps(
                    {
                        "ts": datetime.now(timezone.utc).isoformat(),
                        "method": self.command,
                        "route": route,
                        "status": code,
                        "duration_ms": round((time.perf_counter() - started) * 1000, 2),
                    }
                )
            )

    # ---- verbs -----------------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802 (http.server naming)
        started, route = time.perf_counter(), self._route()
        try:
            if route == "/healthz":
                self._send(200, {"status": "ok"})
            elif route == "/readyz":
                ready = self.server.ready  # type: ignore[attr-defined]
                self._send(200 if ready else 503, {"ready": ready})
            elif route == "/metrics":
                self._send(200, generate_latest(), CONTENT_TYPE_LATEST)
            elif route == "/":
                self._send(
                    200,
                    {
                        "service": SERVICE,
                        "version": VERSION,
                        "host": socket.gethostname(),
                        "endpoints": ["/check", "/v1/score", "/healthz", "/readyz", "/metrics"],
                    },
                )
            elif route == "/check":
                if self._faults():
                    return
                sample = {"amount": random.choice([45, 1200, 2500, 12000]), "country": "CA"}
                result = score_transaction(sample)
                DECISIONS.labels(result["decision"]).inc()
                self._send(
                    200,
                    {
                        "service": SERVICE,
                        "host": socket.gethostname(),
                        "sample": sample,
                        **result,
                        "checked_at": datetime.now(timezone.utc).isoformat(),
                    },
                )
            else:
                self._send(404, {"error": "not found"})
        finally:
            self._observe(route, started)

    def do_POST(self) -> None:  # noqa: N802
        started, route = time.perf_counter(), self._route()
        try:
            if route != "/v1/score":
                self._send(404, {"error": "not found"})
                return
            if self._faults():
                return
            length = int(self.headers.get("Content-Length", "0") or 0)
            if length > 64 * 1024:
                self._send(413, {"error": "body too large"})
                return
            try:
                txn = json.loads(self.rfile.read(length) or b"{}")
                result = score_transaction(txn)
            except (json.JSONDecodeError, ValidationError) as exc:
                self._send(400, {"error": str(exc)})
                return
            DECISIONS.labels(result["decision"]).inc()
            self._send(200, result)
        finally:
            self._observe(route, started)

    def log_message(self, *args) -> None:  # silence default access log; we log JSON
        pass


def build_server(port: int) -> ThreadingHTTPServer:
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)  # noqa: S104 (container listens on all interfaces)
    server.ready = True  # type: ignore[attr-defined]
    server.daemon_threads = True
    return server


def main() -> None:
    port = int(os.environ.get("PORT", "8080"))
    server = build_server(port)

    def shutdown(signum, _frame):
        # Fail readiness first so the load balancer drains us, then stop.
        log.info(json.dumps({"event": "shutdown", "signal": signum}))
        server.ready = False  # type: ignore[attr-defined]
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    log.info(json.dumps({"event": "start", "service": SERVICE, "version": VERSION, "port": port}))
    server.serve_forever()


if __name__ == "__main__":
    main()
