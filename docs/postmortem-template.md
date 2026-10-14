# Postmortem: <short title>

> Blameless: we look for causes in systems and processes, not people.

| Field | Value |
|---|---|
| Date | YYYY-MM-DD |
| Authors | |
| Status | Draft / Reviewed / Action items complete |
| Severity | Page / Ticket |
| Services | Customer portal / Fraud API / Data / Connectivity |
| Detection | Alert name, or how it was noticed |
| Duration | Start → mitigated → resolved (UTC) |

## Summary

Two or three sentences: what broke, who was affected, how long, how it was fixed.

## Impact

- Customer impact (requests failed, latency, features unavailable):
- SLO impact: SLI during the incident, **error budget consumed** (e.g. 38 % of the monthly budget):
- Data impact (none / delayed / lost):

## Timeline (UTC)

| Time | Event |
|---|---|
| hh:mm | First symptom (from logs/metrics) |
| hh:mm | Alert fired |
| hh:mm | Acknowledged |
| hh:mm | Mitigation applied |
| hh:mm | SLI back above target |

## Root cause and trigger

What changed or failed (trigger), and why the system let it hurt customers (root cause). Use "5 whys" if helpful.

## What went well / what went badly / where we got lucky

-
-
-

## Action items

| Action | Type (prevent / detect / mitigate) | Owner | Issue |
|---|---|---|---|
| | | | #NN |

## Evidence

Dashboard screenshots, KQL queries, `game-day-*.log` probe files, alert payloads.
