#!/bin/bash
# =============================================================
# full_deployment_demo.sh
#
# Demonstrates the same hijack scenario when BOTH R1 and R2
# enforce validator-backed RPKI policy.
# =============================================================
LAB="bgp-hijack-rpki"
R1="clab-${LAB}-r1"; R2="clab-${LAB}-r2"; R4="clab-${LAB}-r4"
BOLD="\033[1m"; RED="\033[31m"; GREEN="\033[32m"
YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

SCRIPT_DIR="$(dirname "$0")"

echo -e "${BOLD}================================================${RESET}"
echo -e "${BOLD}  FULL DEPLOYMENT DEMO: R1 + R2 Protected${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo ""
echo -e "Scenario: R1 and R2 both deploy validator-backed RPKI policy."
echo -e "Question: Does AS400 exact-prefix hijack still propagate?"
echo ""

echo -e "${CYAN}Phase 1 - Applying mitigation on R1 and R2${RESET}"
bash "${SCRIPT_DIR}/apply_mitigation.sh" all

echo ""
echo -e "${CYAN}Phase 2 - Launching exact prefix hijack from AS400${RESET}"
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "network 13.0.0.0/24" \
  -c "end" \
  -c "write memory"
docker exec "$R4" ip route add 13.0.0.0/24 via 127.0.0.1 dev lo 2>/dev/null || true

echo "Waiting 15s for BGP convergence..."
sleep 15

echo ""
echo -e "${YELLOW}--- R1 BGP table for 13.0.0.0/24 ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo -e "${YELLOW}--- R2 BGP table for 13.0.0.0/24 ---${RESET}"
docker exec "$R2" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo -e "${YELLOW}--- RPKI cache status on R1 ---${RESET}"
docker exec "$R1" vtysh -c "show rpki cache-connection"

echo ""
echo -e "${YELLOW}--- RPKI cache status on R2 ---${RESET}"
docker exec "$R2" vtysh -c "show rpki cache-connection"

echo ""
echo -e "${BOLD}================================================${RESET}"
echo -e "${GREEN}Expected outcome:${RESET} AS400 hijack is rejected under full deployment"
echo -e "${GREEN}Result focus:${RESET} compare this with partial deployment demo"
echo -e "${BOLD}================================================${RESET}"

echo ""
echo -e "${CYAN}Cleaning up...${RESET}"
bash "${SCRIPT_DIR}/stop_attack.sh"
bash "${SCRIPT_DIR}/remove_mitigation.sh" all
echo -e "${GREEN}Done. Lab restored to clean state.${RESET}"
