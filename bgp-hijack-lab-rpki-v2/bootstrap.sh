#!/bin/bash
# =============================================================
# bootstrap.sh � Installer for the RPKI-enabled duplicate lab
# =============================================================

set -e

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
CYAN="\033[36m"; BOLD="\033[1m"; RESET="\033[0m"

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}???  $*  ???${RESET}"; }

if [ "$EUID" -ne 0 ]; then
  error "Please run as root: sudo bash bootstrap.sh"
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

echo -e "${BOLD}"
echo "+--------------------------------------------------+"
echo "�     BGP Hijack Lab (Duplicate) + RPKI Setup      �"
echo "�      Ubuntu 22.04  |  Containerlab + FRR         �"
echo "+--------------------------------------------------+"
echo -e "${RESET}"

section "Step 1 / 5 � System Update"
apt-get update -qq
apt-get install -y -qq \
  curl wget git unzip tcpdump wireshark-common \
  net-tools iproute2 iputils-ping \
  ca-certificates gnupg lsb-release jq tree
success "System packages installed"

section "Step 2 / 5 � Install Docker"
if command -v docker &>/dev/null; then
  warn "Docker already installed � skipping"
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
  warn "Added $REAL_USER to docker group � log out/in or run: newgrp docker"
fi

section "Step 3 / 5 � Install Containerlab"
if command -v containerlab &>/dev/null; then
  warn "Containerlab already installed � skipping"
else
  bash -c "$(curl -sL https://get.containerlab.dev)" -- -v 0.54.2
  success "Containerlab installed"
fi

section "Step 4 / 5 � Pull Required Images"
images=(
  "quay.io/frrouting/frr:9.1.0"
  "nlnetlabs/routinator:latest"
)
for img in "${images[@]}"; do
  if docker image inspect "$img" &>/dev/null; then
    warn "Image already present � $img"
  else
    info "Pulling $img"
    docker pull "$img"
  fi
done
success "Images ready"

section "Step 5 / 5 � Next Steps"
warn "This bootstrap does not overwrite lab files."
warn "Run from this duplicate repo directory to deploy the RPKI lab."

echo ""
echo -e "${BOLD}Deploy:${RESET}"
echo -e "  ${GREEN}sudo containerlab deploy -t topology.yaml${RESET}"
echo -e "  ${GREEN}bash scripts/verify.sh${RESET}"
echo ""
echo -e "${BOLD}Enable validator-backed mitigation:${RESET}"
echo -e "  ${CYAN}bash scripts/apply_mitigation.sh r1${RESET}"
echo -e "  ${CYAN}bash scripts/validator_status.sh${RESET}"
echo ""
echo -e "${BOLD}Teardown:${RESET}"
echo -e "  ${YELLOW}sudo containerlab destroy -t topology.yaml${RESET}"
