#!/bin/bash
LAB="bgp-hijack"; R1="clab-${LAB}-r1"
BOLD="\033[1m"; YELLOW="\033[33m"; RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${YELLOW}[MITIGATION] Removing filter from R1${RESET}"
echo -e "${BOLD}================================================${RESET}"

docker exec -i "$R1" vtysh << 'EOF'
configure terminal
router bgp 100
 address-family ipv4 unicast
  no neighbor 10.14.0.2 route-map VALIDATE_R4_IN in
 exit-address-family
exit
no route-map VALIDATE_R4_IN
no ip prefix-list BLOCK_VICTIM
no ip prefix-list LEGIT_VICTIM
end
clear bgp 10.14.0.2 in
write memory
EOF

echo ""
echo -e "${YELLOW}[OK] Mitigation removed. R1 is now unprotected.${RESET}"
echo ""
echo -e "${YELLOW}Verifying clean state...${RESET}"
docker exec "$R1" vtysh -c "show ip prefix-list"
docker exec "$R1" vtysh -c "show route-map"
