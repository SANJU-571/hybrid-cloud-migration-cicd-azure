import json
import sys
import threading
import urllib.error
import urllib.request
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import fraud_api  # noqa: E402


# ---- scoring rules -----------------------------------------------------------
def test_small_domestic_purchase_is_approved():
    result = fraud_api.score_transaction({"amount": 45, "country": "CA"})
    assert result["decision"] == "approve"
    assert result["risk_score"] < 0.5


def test_large_cross_border_card_not_present_needs_review():
    result = fraud_api.score_transaction(
        {"amount": 12_000, "country": "US", "card_present": False}
    )
    assert result["decision"] == "review"
    assert any("10,000" in r for r in result["reasons"])


def test_high_risk_country_and_category_is_declined():
    result = fraud_api.score_transaction(
        {"amount": 3_000, "country": "KP", "merchant_category": "crypto"}
    )
    assert result["decision"] == "decline"
    assert result["risk_score"] <= 1.0


@pytest.mark.parametrize(
    "body",
    [{}, {"amount": "abc"}, {"amount": -1}, {"amount": 10, "hour": 25}, ["not", "an", "object"]],
)
def test_invalid_requests_are_rejected(body):
    with pytest.raises(fraud_api.ValidationError):
        fraud_api.score_transaction(body)


# ---- HTTP server ---------------------------------------------------------------
@pytest.fixture(scope="module")
def base_url():
    server = fraud_api.build_server(0)  # port 0 = pick a free port
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{server.server_address[1]}"
    server.shutdown()


def _get(url):
    with urllib.request.urlopen(url, timeout=5) as resp:  # noqa: S310 (local test server)
        return resp.status, resp.read().decode()


def _post(url, payload):
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:  # noqa: S310
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read())


def test_health_and_readiness(base_url):
    assert _get(f"{base_url}/healthz")[0] == 200
    assert _get(f"{base_url}/readyz")[0] == 200


def test_score_endpoint(base_url):
    status, body = _post(f"{base_url}/v1/score", {"amount": 45})
    assert status == 200
    assert body["decision"] == "approve"


def test_score_endpoint_rejects_bad_input(base_url):
    status, body = _post(f"{base_url}/v1/score", {"amount": "lots"})
    assert status == 400
    assert "amount" in body["error"]


def test_portal_check_route_is_backwards_compatible(base_url):
    status, raw = _get(f"{base_url}/check")
    body = json.loads(raw)
    assert status == 200
    assert body["service"] == "fraud-detection"
    assert body["decision"] in {"approve", "review", "decline"}


def test_metrics_expose_red_and_business_metrics(base_url):
    _post(f"{base_url}/v1/score", {"amount": 45})
    status, text = _get(f"{base_url}/metrics")
    assert status == 200
    assert 'http_requests_total{code="200",method="POST",route="/v1/score"}' in text
    assert "http_request_duration_seconds_bucket" in text
    assert 'fraud_decisions_total{decision="approve"}' in text


def test_unknown_route_is_404_and_bucketed(base_url):
    try:
        _get(f"{base_url}/does-not-exist")
    except urllib.error.HTTPError as err:
        assert err.code == 404
    _, text = _get(f"{base_url}/metrics")
    assert 'route="other"' in text


def test_fault_injection_returns_500(base_url, monkeypatch):
    monkeypatch.setenv("FAULT_ERROR_RATE", "1.0")
    status, body = _post(f"{base_url}/v1/score", {"amount": 45})
    assert status == 500
    assert body["error"] == "injected fault"
