#!/bin/bash
# ==========================================================
# BGP DNS Hijack Lab v4 — CLEAN REBUILD (Final v3)
#
# Fix order (critical):
#   1. Deploy containers
#   2. Wait for BGP to converge FIRST (interfaces stabilize)
#   3. Clear BGP sessions + wait for reconnect
#   4. Configure host containers AFTER BGP is up
#   5. Verify everything end to end
#
# Why this order matters:
#   Host container interfaces are not stable immediately after
#   deploy. Waiting for BGP convergence (~90s) ensures all
#   interfaces are fully up before we configure hosts.
#   Configuring hosts before BGP = silent failures on ip/route.
# ==========================================================
set -e
cd "$(dirname "$0")"
LAB="clab-bgp-dns-hijack"

echo "╔══════════════════════════════════════════╗"
echo "║  BGP DNS Hijack Lab v4 — Clean Rebuild   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Step 0: Destroy existing lab ─────────────────────────────
echo "[0/8] Destroying any existing lab..."
sudo containerlab destroy -t topology.yaml --cleanup 2>/dev/null || true
echo "  Done."

# ── Step 1: Create vtysh.conf for all routers ─────────────────
echo ""
echo "[1/8] Creating vtysh.conf for all routers..."
for r in r1 r2 r3 r4 r5 r6; do
  cat > configs/$r/vtysh.conf << 'VEOF'
service integrated-vtysh-config
VEOF
  echo "  configs/$r/vtysh.conf created"
done

# ── Step 2: Rewrite ALL frr.conf files ───────────────────────
echo ""
echo "[2/8] Writing fixed FRR configs..."

cat > configs/r1/frr.conf << 'EOF'
frr defaults traditional
hostname r1
no ipv6 forwarding
!
interface eth1
 ip address 10.12.0.1/30
exit
!
interface eth2
 ip address 10.14.0.1/30
exit
!
interface lo
 ip address 11.0.0.1/24
exit
!
router bgp 100
 bgp router-id 1.1.1.1
 no bgp ebgp-requires-policy
 neighbor 10.12.0.2 remote-as 200
 neighbor 10.14.0.2 remote-as 400
 !
 address-family ipv4 unicast
  network 11.0.0.0/24
  redistribute connected
  neighbor 10.12.0.2 activate
  neighbor 10.14.0.2 activate
 exit-address-family
exit
!
end
EOF
echo "  r1 (AS100) written"

cat > configs/r2/frr.conf << 'EOF'
frr defaults traditional
hostname r2
no ipv6 forwarding
!
interface eth1
 ip address 10.12.0.2/30
exit
!
interface eth2
 ip address 10.23.0.1/30
exit
!
interface eth3
 ip address 10.25.0.1/30
exit
!
interface lo
 ip address 12.0.0.1/24
exit
!
router bgp 200
 bgp router-id 2.2.2.2
 no bgp ebgp-requires-policy
 neighbor 10.12.0.1 remote-as 100
 neighbor 10.23.0.2 remote-as 300
 neighbor 10.25.0.2 remote-as 500
 !
 address-family ipv4 unicast
  network 12.0.0.0/24
  redistribute connected
  neighbor 10.12.0.1 activate
  neighbor 10.23.0.2 activate
  neighbor 10.25.0.2 activate
 exit-address-family
exit
!
end
EOF
echo "  r2 (AS200) written"

cat > configs/r3/frr.conf << 'EOF'
frr defaults traditional
hostname r3
no ipv6 forwarding
!
interface eth1
 ip address 10.23.0.2/30
exit
!
interface eth2
 ip address 10.30.0.1/30
exit
!
interface lo
 ip address 13.0.0.1/24
exit
!
router bgp 300
 bgp router-id 3.3.3.3
 no bgp ebgp-requires-policy
 neighbor 10.23.0.1 remote-as 200
 !
 address-family ipv4 unicast
  network 13.0.0.0/24
  redistribute connected
  neighbor 10.23.0.1 activate
 exit-address-family
exit
!
ip route 13.0.0.50/32 10.30.0.2
!
end
EOF
echo "  r3 (AS300) written"

cat > configs/r4/frr.conf << 'EOF'
frr defaults traditional
hostname r4
no ipv6 forwarding
!
interface eth1
 ip address 10.14.0.2/30
exit
!
interface eth2
 ip address 10.40.0.1/30
exit
!
interface lo
 ip address 14.0.0.1/24
exit
!
router bgp 400
 bgp router-id 4.4.4.4
 no bgp ebgp-requires-policy
 neighbor 10.14.0.1 remote-as 100
 !
 address-family ipv4 unicast
  network 14.0.0.0/24
  redistribute connected
  neighbor 10.14.0.1 activate
 exit-address-family
exit
!
end
EOF
echo "  r4 (AS400) written"

cat > configs/r5/frr.conf << 'EOF'
frr defaults traditional
hostname r5
no ipv6 forwarding
!
interface eth1
 ip address 10.25.0.2/30
exit
!
interface eth2
 ip address 10.56.0.1/30
exit
!
interface lo
 ip address 15.0.0.1/24
exit
!
router bgp 500
 bgp router-id 5.5.5.5
 no bgp ebgp-requires-policy
 neighbor 10.25.0.1 remote-as 200
 neighbor 10.56.0.2 remote-as 600
 !
 address-family ipv4 unicast
  network 15.0.0.0/24
  redistribute connected
  neighbor 10.25.0.1 activate
  neighbor 10.56.0.2 activate
 exit-address-family
exit
!
end
EOF
echo "  r5 (AS500) written"

cat > configs/r6/frr.conf << 'EOF'
frr defaults traditional
hostname r6
no ipv6 forwarding
!
interface eth1
 ip address 10.56.0.2/30
exit
!
interface eth2
 ip address 10.60.0.1/30
exit
!
interface lo
 ip address 16.0.0.1/24
exit
!
router bgp 600
 bgp router-id 6.6.6.6
 no bgp ebgp-requires-policy
 neighbor 10.56.0.1 remote-as 500
 !
 address-family ipv4 unicast
  network 16.0.0.0/24
  redistribute connected
  neighbor 10.56.0.1 activate
 exit-address-family
exit
!
end
EOF
echo "  r6 (AS600) written"

# ── Step 3: Write DNS configs ─────────────────────────────────
echo ""
echo "[3/8] Writing fixed DNS configs..."

cat > configs/dns/legit-dnsmasq.conf << 'EOF'
no-resolv
no-hosts
log-queries
local-ttl=300
address=/www.victim.lab/13.0.0.100
address=/login.victim.lab/13.0.0.80
address=/mail.victim.lab/13.0.0.25
address=/api.victim.lab/13.0.0.90
address=/ns.victim.lab/13.0.0.50
EOF
echo "  legit-dnsmasq.conf written"

cat > configs/dns/fake-dnsmasq.conf << 'EOF'
no-resolv
no-hosts
log-queries
local-ttl=180
address=/www.victim.lab/14.0.0.66
address=/login.victim.lab/14.0.0.66
address=/mail.victim.lab/14.0.0.66
address=/api.victim.lab/14.0.0.66
address=/ns.victim.lab/14.0.0.66
EOF
echo "  fake-dnsmasq.conf written"

cat > configs/dns/unbound.conf << 'EOF'
server:
    interface: 127.0.0.1
    port: 53
    access-control: 127.0.0.0/8 allow
    do-not-query-localhost: no
    verbosity: 1
    val-permissive-mode: yes
    cache-min-ttl: 0
    cache-max-ttl: 86400
    msg-cache-size: 4m
    rrset-cache-size: 4m

forward-zone:
    name: "."
    forward-addr: 13.0.0.50
EOF
echo "  unbound.conf written"

# ── Step 4: Write topology ────────────────────────────────────
echo ""
echo "[4/8] Writing topology.yaml..."

cat > topology.yaml << 'EOF'
name: bgp-dns-hijack

topology:
  nodes:
    r1:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r1/frr.conf:/etc/frr/frr.conf
        - configs/r1/daemons:/etc/frr/daemons
        - configs/r1/vtysh.conf:/etc/frr/vtysh.conf
    r2:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r2/frr.conf:/etc/frr/frr.conf
        - configs/r2/daemons:/etc/frr/daemons
        - configs/r2/vtysh.conf:/etc/frr/vtysh.conf
    r3:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r3/frr.conf:/etc/frr/frr.conf
        - configs/r3/daemons:/etc/frr/daemons
        - configs/r3/vtysh.conf:/etc/frr/vtysh.conf
    r4:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r4/frr.conf:/etc/frr/frr.conf
        - configs/r4/daemons:/etc/frr/daemons
        - configs/r4/vtysh.conf:/etc/frr/vtysh.conf
    r5:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r5/frr.conf:/etc/frr/frr.conf
        - configs/r5/daemons:/etc/frr/daemons
        - configs/r5/vtysh.conf:/etc/frr/vtysh.conf
    r6:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r6/frr.conf:/etc/frr/frr.conf
        - configs/r6/daemons:/etc/frr/daemons
        - configs/r6/vtysh.conf:/etc/frr/vtysh.conf

    dns-server:
      kind: linux
      image: dns-lab:latest
      binds:
        - configs/dns/legit-dnsmasq.conf:/etc/dnsmasq.conf

    fake-dns:
      kind: linux
      image: dns-lab:latest
      binds:
        - configs/dns/fake-dnsmasq.conf:/etc/dnsmasq.conf

    client:
      kind: linux
      image: dns-lab:latest
      binds:
        - configs/dns/unbound.conf:/etc/unbound/unbound.conf

  links:
    - endpoints: ["r1:eth1", "r2:eth1"]
    - endpoints: ["r2:eth2", "r3:eth1"]
    - endpoints: ["r1:eth2", "r4:eth1"]
    - endpoints: ["r2:eth3", "r5:eth1"]
    - endpoints: ["r5:eth2", "r6:eth1"]
    - endpoints: ["r3:eth2", "dns-server:eth1"]
    - endpoints: ["r4:eth2", "fake-dns:eth1"]
    - endpoints: ["r6:eth2", "client:eth1"]
EOF
echo "  topology.yaml written"

# ── Step 5: Deploy ────────────────────────────────────────────
echo ""
echo "[5/8] Deploying lab..."
sudo containerlab deploy -t topology.yaml

# Enable IP forwarding immediately after deploy
echo "  Enabling IP forwarding on routers..."
for r in r1 r2 r3 r4 r5 r6; do
  docker exec $LAB-$r sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
done

# ── Step 6: Wait for BGP to converge FIRST ───────────────────
echo ""
echo "[6/8] Waiting 90s for BGP convergence..."
echo "  (host containers configured AFTER BGP stabilizes)"
sleep 90


# ── Step 7: Configure host containers AFTER BGP is up ────────
echo ""
echo "[7/8] Configuring host containers (interfaces now stable)..."

echo "  Configuring dns-server..."
docker exec $LAB-dns-server sh -c "
  ip addr add 10.30.0.2/30 dev eth1 2>/dev/null || true
  ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
  ip link set eth1 up
  ip route del default 2>/dev/null || true
  ip route add default via 10.30.0.1
  pkill dnsmasq 2>/dev/null || true
  sleep 1
  dnsmasq &
" && echo "    done"

echo "  Configuring fake-dns..."
docker exec $LAB-fake-dns sh -c "
  ip addr add 10.40.0.2/30 dev eth1 2>/dev/null || true
  ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
  ip link set eth1 up
  ip route del default 2>/dev/null || true
  ip route add default via 10.40.0.1
  pkill dnsmasq 2>/dev/null || true
  sleep 1
  dnsmasq &
" && echo "    done"

echo "  Configuring client..."
docker exec $LAB-client sh -c "
  ip addr add 10.60.0.2/30 dev eth1 2>/dev/null || true
  ip link set eth1 up
  ip route del default 2>/dev/null || true
  ip route add default via 10.60.0.1
  pkill unbound 2>/dev/null || true
  sleep 1
  unbound -c /etc/unbound/unbound.conf &
" && echo "    done"

echo "  Waiting 10s for services to start..."
sleep 10

# ── Step 8: Verify everything ─────────────────────────────────
echo ""
echo "[8/8] Verifying lab..."
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║            Verification                  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

echo "[1] BGP sessions on R1 (AS100):"
docker exec $LAB-r1 vtysh -c "show bgp ipv4 unicast summary" 2>/dev/null | tail -5
echo ""

echo "[2] BGP sessions on R6 (AS600):"
docker exec $LAB-r6 vtysh -c "show bgp ipv4 unicast summary" 2>/dev/null | tail -5
echo ""

echo "[3] Route to 13.0.0.0/24 from R6:"
docker exec $LAB-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null | grep -E "AS path|best"
echo ""

echo "[4] Ping 13.0.0.50 from client:"
if docker exec $LAB-client ping -c 2 -W 3 13.0.0.50 >/dev/null 2>&1; then
  echo "  ✓ 13.0.0.50 reachable"
else
  echo "  ✗ Ping failed — re-running host bootstrap..."
  docker exec $LAB-dns-server sh -c "
    ip addr add 10.30.0.2/30 dev eth1 2>/dev/null || true
    ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
    ip link set eth1 up
    ip route del default 2>/dev/null || true
    ip route add default via 10.30.0.1
    pkill dnsmasq 2>/dev/null || true
    sleep 1
    dnsmasq &
  " 2>/dev/null
  docker exec $LAB-fake-dns sh -c "
    ip addr add 10.40.0.2/30 dev eth1 2>/dev/null || true
    ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
    ip link set eth1 up
    ip route del default 2>/dev/null || true
    ip route add default via 10.40.0.1
    pkill dnsmasq 2>/dev/null || true
    sleep 1
    dnsmasq &
  " 2>/dev/null
  docker exec $LAB-client sh -c "
    ip addr add 10.60.0.2/30 dev eth1 2>/dev/null || true
    ip link set eth1 up
    ip route del default 2>/dev/null || true
    ip route add default via 10.60.0.1
    pkill unbound 2>/dev/null || true
    sleep 1
    unbound -c /etc/unbound/unbound.conf &
  " 2>/dev/null
  sleep 10
  if docker exec $LAB-client ping -c 2 -W 3 13.0.0.50 >/dev/null 2>&1; then
    echo "  ✓ 13.0.0.50 reachable after retry"
  else
    echo "  ✗ Still not reachable — check BGP sessions above"
  fi
fi
echo ""

echo "[5] DNS test from client (direct to 13.0.0.50):"
RESULT=$(docker exec $LAB-client dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
echo "  www.victim.lab = $RESULT"
echo ""

echo "[6] DNS test from client (through caching resolver):"
CACHED=$(docker exec $LAB-client dig @127.0.0.1 www.victim.lab +short +timeout=5 2>/dev/null)
echo "  www.victim.lab = $CACHED"
echo ""

# ── Final status ──────────────────────────────────────────────
if [ "$RESULT" = "13.0.0.100" ]; then
  echo "╔══════════════════════════════════════════╗"
  echo "║  ✓ Lab is READY!                         ║"
  echo "║                                          ║"
  echo "║  Run: bash scripts/full_demo.sh          ║"
  echo "║   or: bash scripts/evaluate_dns_chain.sh ║"
  echo "╚══════════════════════════════════════════╝"
elif [ -z "$RESULT" ]; then
  echo "╔══════════════════════════════════════════╗"
  echo "║  ✗ DNS not reachable yet                 ║"
  echo "║                                          ║"
  echo "║  BGP may still be converging. Try:       ║"
  echo "║  docker exec $LAB-client \               ║"
  echo "║    dig @13.0.0.50 www.victim.lab +short  ║"
  echo "╚══════════════════════════════════════════╝"
else
  echo "  Unexpected DNS result: $RESULT"
  echo "  Expected: 13.0.0.100"
fi
