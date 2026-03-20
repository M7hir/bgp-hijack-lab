#!/bin/bash
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  BGP Hijack -> DNS Cache Poisoning — Full Demo          ║"
echo "║  Attack Chain + Mitigation                               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Press ENTER to proceed through each phase..."
read -p ""

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/dns_baseline.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to launch the attack..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/start_dns_hijack.sh
echo "────────────────────────────────────────────────────────────"
sleep 3
read -p "Press ENTER to verify DNS poisoning..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/verify_dns_poison.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to withdraw the hijack..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/stop_dns_hijack.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to verify cache persistence..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/verify_cache_persistence.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to apply ROV mitigation..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/mitigate_rov.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to test mitigation blocks the attack..."

echo ""
echo "────────────────────────────────────────────────────────────"
echo "=== Phase 7: Proving ROV Mitigation Blocks the Attack ==="
echo ""
LAB="clab-bgp-dns-hijack"

bash scripts/start_dns_hijack.sh
sleep 3

echo ""
echo "[1] Check if hijack propagated past R1:"
HAS_HIJACK=$(docker exec ${LAB}-r6 vtysh \
  -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null | grep -c "best" || true)
if [ "$HAS_HIJACK" -eq 0 ]; then
  echo "    ✓ 13.0.0.0/25 NOT in R6 BGP table — hijack blocked by R1"
else
  echo "    ✗ 13.0.0.0/25 in R6 BGP table — check mitigation"
fi

echo ""
echo "[2] DNS test with mitigation active (should stay legitimate):"
DIRECT=$(docker exec ${LAB}-client \
  dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
CACHED=$(docker exec ${LAB}-client \
  dig @127.0.0.1 www.victim.lab +short +timeout=5 2>/dev/null)
echo "    Direct:  www.victim.lab -> $DIRECT"
echo "    Cached:  www.victim.lab -> $CACHED"

echo ""
if [ "$DIRECT" = "13.0.0.100" ] && [ "$CACHED" = "13.0.0.100" ]; then
  echo "*** MITIGATION SUCCESSFUL ***"
  echo "Both direct and cached DNS return legitimate answer"
  echo "BGP hijack blocked — DNS cache never poisoned"
fi

echo ""
echo "[3] Cleaning up..."
bash scripts/stop_dns_hijack.sh > /dev/null 2>&1
bash scripts/remove_rov.sh > /dev/null 2>&1
echo "    Lab restored to clean state"
echo "────────────────────────────────────────────────────────────"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Demo Complete                                           ║"
echo "║                                                          ║"
echo "║  Key Finding: A brief BGP sub-prefix hijack produces     ║"
echo "║  DNS cache poisoning that persists for HOURS after       ║"
echo "║  the routing attack ends.                                ║"
echo "║                                                          ║"
echo "║  Mitigation: ROV filtering on R1 blocks the hijack      ║"
echo "║  before it propagates — DNS stays clean.                 ║"
echo "║                                                          ║"
echo "║  Attack: seconds  |  Poison: TTL-dependent               ║"
echo "║  ROV blocks: <5s  |  DNS stays: clean                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
