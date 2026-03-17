#!/bin/bash
LAB="bgp-hijack-rpki"
R1="clab-${LAB}-r1"
VALIDATOR="clab-${LAB}-rpki"

BOLD="\033[1m"; CYAN="\033[36m"; YELLOW="\033[33m"; RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${CYAN}[RPKI] Validator and Cache Status${RESET}"
echo -e "${BOLD}================================================${RESET}"

docker ps --filter "name=${VALIDATOR}" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

echo ""
echo -e "${CYAN}R1 cache connection:${RESET}"
docker exec "$R1" vtysh -c "show rpki cache-connection"

echo ""
echo -e "${CYAN}R1 route-map state:${RESET}"
docker exec "$R1" vtysh -c "show route-map"

echo ""
echo -e "${YELLOW}Tip:${RESET} Use scripts/apply_mitigation.sh r1 or scripts/apply_mitigation.sh all"
