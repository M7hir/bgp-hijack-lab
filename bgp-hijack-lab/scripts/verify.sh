#!/bin/bash
# =============================================================
# verify.sh — Check BGP state on all routers
# Run after deploying the lab to confirm convergence
# =============================================================

LAB="bgp-hijack"

R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
R3="clab-${LAB}-r3"
R4="clab-${LAB}-r4"

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

run_vtysh() {
  local node=$1
  local cmd=$2
  docker exec "$node" vtysh -c "$cmd" 2>/dev/null
}

echo -e "${BOLD}================================================${RESET}"
echo -e "${BOLD} BGP Hijack Lab — Verification${RESET}"
echo -e "${BOLD}================================================${RESET}"

echo -e "\n${CYAN}[R1 AS100] BGP Summary${RESET}"
run_vtysh "$R1" "show bgp summary"

echo -e "\n${CYAN}[R1 AS100] BGP Table — Watch for 13.0.0.0 entries${RESET}"
run_vtysh "$R1" "show bgp ipv4 unicast"

echo -e "\n${CYAN}[R2 AS200] BGP Table${RESET}"
run_vtysh "$R2" "show bgp ipv4 unicast"

echo -e "\n${CYAN}[R3 AS300 VICTIM] BGP Table${RESET}"
run_vtysh "$R3" "show bgp ipv4 unicast"

echo -e "\n${CYAN}[R4 AS400 ATTACKER] BGP Table${RESET}"
run_vtysh "$R4" "show bgp ipv4 unicast"

echo -e "\n${CYAN}[R1] IP Routing Table${RESET}"
run_vtysh "$R1" "show ip route"

echo -e "\n${BOLD}================================================${RESET}"
echo -e "${GREEN}Legitimate path to 13.0.0.0/24 should be:${RESET}"
echo -e "  R1 → R2(AS200) → R3(AS300)   [AS path: 200 300]"
echo -e "${YELLOW}After exact hijack:${RESET}"
echo -e "  R1 → R4(AS400)               [AS path: 400 — shorter, wins]"
echo -e "${YELLOW}After subprefix hijack:${RESET}"
echo -e "  R1 → R4(AS400) for /25       [more specific prefix wins]"
echo -e "  R1 → R2 → R3  for /24        [original /24 still in table]"
echo -e "${BOLD}================================================${RESET}"
