"""Steady synthetic traffic for the local observability lab (stdlib only)."""

import json
import os
import random
import time
import urllib.error
import urllib.request

TARGET = os.environ.get("TARGET", "http://localhost:8080")
RPS = float(os.environ.get("RPS", "10"))

SAMPLES = [
    {"amount": 45, "country": "CA"},
    {"amount": 2_500, "country": "CA", "merchant_category": "electronics"},
    {"amount": 12_000, "country": "US", "card_present": False},
    {"amount": 800, "country": "KP", "merchant_category": "crypto"},
]

while True:
    body = json.dumps(random.choice(SAMPLES)).encode()
    req = urllib.request.Request(
        f"{TARGET}/v1/score", data=body, headers={"Content-Type": "application/json"}
    )
    try:
        urllib.request.urlopen(req, timeout=2).read()  # noqa: S310 (fixed local URL)
    except (urllib.error.URLError, TimeoutError):
        pass  # errors are what the SLO dashboard is for
    time.sleep(1 / RPS)
