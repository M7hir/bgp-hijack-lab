#!/bin/bash
# =============================================================
# stop_attack.sh — Withdraw all hijacked routes from AS400
# BGP will reconverge and traffic returns to legitimate AS300
# =============================================================

LAB="bgp-hijack"
R4="clab-${LAB}-r4"
R1="clab-${LAB}-r1"

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${GREEN}[STOP] Withdrawing hijacked routes from AS400${RESET}"
echo -e "${BOLD}================================================${RESET}"

docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "no network 13.0.0.0/25" \
  -c "end" \
  -c "write memory"

docker exec "$R4" ip route del 13.0.0.0/24 dev lo 2>/dev/null || true
docker exec "$R4" ip route del 13.0.0.0/25 dev lo 2>/dev/null || true

echo "Waiting 10 seconds for BGP convergence..."
sleep 10

echo ""
echo -e "${YELLOW}--- R1 BGP Table After Attack Stopped ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"

echo ""
echo -e "${GREEN}Expected: 13.0.0.0/24 back via AS200 AS300 (legitimate path)${RESET}"
echo -e "${BOLD}================================================${RESET}"
