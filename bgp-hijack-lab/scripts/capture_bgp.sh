#!/bin/bash
# =============================================================
# capture_bgp.sh — Capture BGP UPDATE packets for report evidence
#
# Captures BGP traffic (TCP port 179) on the R1-R4 link.
# Run this BEFORE launching an attack, then trigger the attack
# in another terminal to capture the UPDATE messages.
#
# Output: bgp_capture_<timestamp>.pcap
# Open with Wireshark for analysis.
# =============================================================

LAB="bgp-hijack"
R1="clab-${LAB}-r1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT="bgp_capture_${TIMESTAMP}.pcap"

BOLD="\033[1m"
CYAN="\033[36m"
RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${CYAN} BGP Packet Capture on R1 (all interfaces)${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo "Capturing BGP traffic (port 179) on R1..."
echo "Output: ${OUTPUT}"
echo ""
echo "Open a second terminal and run one of:"
echo "  scripts/start_exact_hijack.sh"
echo "  scripts/start_subprefix_hijack.sh"
echo ""
echo "Press Ctrl+C to stop capture."
echo -e "${BOLD}================================================${RESET}"

# Capture on all interfaces inside R1 container, filter BGP port 179
docker exec "$R1" tcpdump -i any -w - port 179 2>/dev/null > "$OUTPUT"

echo ""
echo "Capture saved to: ${OUTPUT}"
echo "View with: wireshark ${OUTPUT}"
