#!/usr/bin/env bash
# Game day: inject a real failure into a deployed environment and measure what
# customers would have seen, against the SLOs in docs/SRE.md.
#
#   web-instance  power off one web VM Scale Set instance
#                 hypothesis: WAF/LB health probes drain it, portal availability stays >= 99.5%
#   fraud-vm      stop the private fraud-detection VM
#                 hypothesis: /api/fraud/check fails, but the portal home page stays up
#                 (the dependency fails "soft" and only the fraud route is affected)
#
# The script probes the public portal every 0.5 s for a baseline, during the fault
# and after recovery, then prints availability and the longest outage. Write the
# result up with docs/postmortem-template.md.
#
# Usage: ./scripts/game-day.sh <name-prefix> <web-instance|fraud-vm> [fault-seconds]
#        e.g. ./scripts/game-day.sh nfb-lab web-instance 180
set -euo pipefail

PREFIX="${1:-nfb-lab}"
EXPERIMENT="${2:-web-instance}"
FAULT_SECONDS="${3:-180}"
RG_AZ="rg-${PREFIX}-azure"
WORKDIR="$(mktemp -d)"
trap 'kill "${PROBE_PID:-0}" 2>/dev/null || true; rm -rf "$WORKDIR"' EXIT

FQDN="$(az network public-ip show -g "$RG_AZ" -n "pip-${PREFIX}-ingress" --query dnsSettings.fqdn -o tsv)"
case "$EXPERIMENT" in
  web-instance) PROBE_PATH="/" ;;
  fraud-vm) PROBE_PATH="/api/fraud/check" ;;
  *) echo "unknown experiment: $EXPERIMENT (web-instance | fraud-vm)"; exit 2 ;;
esac
URL="http://${FQDN}${PROBE_PATH}"

probe() { # writes "<epoch> <phase> <http_code>" lines until killed
  while true; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL" || true)"
    echo "$(date +%s) $(cat "$WORKDIR/phase") $code" >> "$WORKDIR/probes.log"
    sleep 0.5
  done
}

phase() { echo "$1" > "$WORKDIR/phase"; echo "== $(date -u +%H:%M:%SZ) phase: $1"; }

echo "== Game day: $EXPERIMENT on $PREFIX (probing $URL)"
phase baseline
probe & PROBE_PID=$!
sleep 60

phase fault
if [[ "$EXPERIMENT" == "web-instance" ]]; then
  VMSS="vmss-${PREFIX}-web"
  INSTANCE="$(az vmss list-instances -g "$RG_AZ" -n "$VMSS" --query '[0].instanceId' -o tsv)"
  echo "   powering off $VMSS instance $INSTANCE"
  az vmss power-off -g "$RG_AZ" -n "$VMSS" --instance-ids "$INSTANCE" --skip-shutdown -o none
  sleep "$FAULT_SECONDS"
  phase recovery
  az vmss start -g "$RG_AZ" -n "$VMSS" --instance-ids "$INSTANCE" -o none
else
  VM="vm-${PREFIX}-fraud"
  echo "   stopping $VM"
  az vm stop -g "$RG_AZ" -n "$VM" --skip-shutdown -o none
  sleep "$FAULT_SECONDS"
  phase recovery
  az vm start -g "$RG_AZ" -n "$VM" -o none
fi
sleep 120
kill "$PROBE_PID"

echo
echo "== Results (SLO: 99.5% of requests succeed)"
awk '
  { total[$2]++; if ($3 !~ /^[23]/) { bad[$2]++; run++; if (run > maxrun) maxrun = run } else run = 0 }
  END {
    split("baseline fault recovery", order, " ")
    for (i = 1; i <= 3; i++) {
      p = order[i]; t = total[p] + 0; b = bad[p] + 0
      printf "   %-9s requests=%-5d failed=%-5d availability=%6.2f%%\n", p, t, b, t ? 100 * (t - b) / t : 0
    }
    printf "   longest consecutive failure streak: %d probes (~%.1f s)\n", maxrun, maxrun * 0.5
  }' "$WORKDIR/probes.log"
cp "$WORKDIR/probes.log" "game-day-${EXPERIMENT}-$(date +%Y%m%d-%H%M).log"
echo "   raw probes saved to game-day-${EXPERIMENT}-*.log - attach them to the write-up."
