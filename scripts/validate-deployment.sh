#!/usr/bin/env bash
# End-to-end validation of a deployed environment (deck: "Testing & Validation").
#   1. Web tier answers through the public entry point (WAF / LB); WAF blocks SQLi
#   2. Web -> private fraud-detection tier works (east-west)
#   3. Cisco ACLs, now NSGs, behave as designed - tested from real VMs in the
#      simulated on-prem network with `az vm run-command`.
#
# Usage: ./scripts/validate-deployment.sh <name-prefix>      e.g. nfb-lab
set -uo pipefail

PREFIX="${1:-nfb-lab}"
RG_AZ="rg-${PREFIX}-azure"
RG_OP="rg-${PREFIX}-onprem-sim"
PASS=0
FAIL=0

result() { # name expected actual
  if [[ "$2" == "$3" ]]; then
    printf '  \e[32mPASS\e[0m  %-58s (expected %s, got %s)\n' "$1" "$2" "$3"
    PASS=$((PASS + 1))
  else
    printf '  \e[31mFAIL\e[0m  %-58s (expected %s, got %s)\n' "$1" "$2" "$3"
    FAIL=$((FAIL + 1))
  fi
}

echo "== Discovering resources ($PREFIX)"
FQDN="$(az network public-ip show -g "$RG_AZ" -n "pip-${PREFIX}-ingress" --query dnsSettings.fqdn -o tsv)"
SQL_FQDN="$(az sql server list -g "$RG_AZ" --query "[0].fullyQualifiedDomainName" -o tsv)"
echo "   portal : http://$FQDN"
echo "   sql    : $SQL_FQDN (private endpoint)"

echo
echo "== 1. Web tier & east-west traffic"
code="000"
for _ in $(seq 1 30); do # instances need a few minutes for cloud-init
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$FQDN/health" || true)"
  [[ "$code" == "200" ]] && break
  sleep 20
done
result "Portal /health via public entry point" 200 "$code"

hosts="$(for _ in $(seq 1 10); do curl -s --max-time 5 "http://$FQDN/" | grep -o 'vmss-[a-z0-9_-]*' | head -1; done | sort -u | wc -l | tr -d ' ')"
result "Load balancing spreads requests over >1 instance" "true" "$([[ "$hosts" -gt 1 ]] && echo true || echo false)"

fraud="$(curl -s --max-time 10 "http://$FQDN/api/fraud/check" | grep -c '"service": "fraud-detection"' || true)"
result "Web -> private fraud-detection API (port 8080)" 1 "$fraud"

if [[ "$(az network application-gateway list -g "$RG_AZ" --query "length(@)" -o tsv)" -gt 0 ]]; then
  waf="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$FQDN/?id=1%27%20OR%20%271%27%3D%271" || true)"
  result "WAF blocks a SQL-injection attempt (OWASP 3.2)" 403 "$waf"
fi

# TCP probe executed *inside* a VM. Prints OPEN or CLOSED.
probe_script() {
  cat <<EOF
probe() { if timeout 4 bash -c "</dev/tcp/\$1/\$2" 2>/dev/null; then echo "\$3=OPEN"; else echo "\$3=CLOSED"; fi; }
probe $SQL_FQDN 1433 cloud_sql
probe 192.168.102.10 1433 onprem_db
probe 192.168.30.10 22 manager_pc
probe 192.168.40.10 22 employee_pc
getent hosts $SQL_FQDN | awk '{print "sql_ip="\$1}'
EOF
}

run_on() { # vm
  az vm run-command invoke -g "$RG_OP" -n "$1" --command-id RunShellScript \
    --scripts "$(probe_script)" --query "value[0].message" -o tsv 2>/dev/null
}

get() { echo "$1" | grep -o "$2=[A-Z0-9.]*" | head -1 | cut -d= -f2; }

echo
echo "== 2. Manager PC (VLAN 30, 192.168.30.10)"
M="$(run_on vm-manager-pc)"
echo "   cloud SQL resolves to private IP: $(get "$M" sql_ip)"
result "ACL 110: Manager -> Azure SQL (private endpoint) permitted" OPEN "$(get "$M" cloud_sql)"
result "ACL 120: Manager -> on-prem DB permitted" OPEN "$(get "$M" onprem_db)"
result "ACL 140: Manager -> Employee VLAN denied" CLOSED "$(get "$M" employee_pc)"

echo
echo "== 3. Employee PC (VLAN 40, 192.168.40.10)"
E="$(run_on vm-employee-pc)"
result "ACL 110: Employee -> Azure SQL denied" CLOSED "$(get "$E" cloud_sql)"
result "ACL 120: Employee -> on-prem DB permitted" OPEN "$(get "$E" onprem_db)"
result "ACL 130: Employee -> Manager VLAN denied" CLOSED "$(get "$E" manager_pc)"

echo
echo "== Summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
