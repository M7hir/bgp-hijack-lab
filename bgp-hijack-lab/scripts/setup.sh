#!/bin/bash
# =============================================================
# setup.sh — Install Containerlab and pull FRR image
# Run this ONCE on a fresh Ubuntu 22.04 machine
# =============================================================

set -e

echo "================================================"
echo " BGP Hijack Lab — Environment Setup"
echo "================================================"

# 1. System update
echo "[1/5] Updating system packages..."
sudo apt-get update -qq
sudo apt-get install -y curl wget git docker.io jq tcpdump

# 2. Enable and start Docker
echo "[2/5] Starting Docker..."
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$USER"

# 3. Install Containerlab
echo "[3/5] Installing Containerlab..."
bash -c "$(curl -sL https://get.containerlab.dev)"

# 4. Pull FRR image
echo "[4/5] Pulling FRR Docker image (frrouting/frr:v9.1.0)..."
sudo docker pull frrouting/frr:v9.1.0

# 5. Verify
echo "[5/5] Verifying installation..."
containerlab version
docker images | grep frr

echo ""
echo "================================================"
echo " Setup complete!"
echo " NOTE: Log out and back in for docker group"
echo "       membership to take effect, OR run:"
echo "       newgrp docker"
echo ""
echo " Then start the lab with:"
echo "   sudo containerlab deploy -t topology.yaml"
echo "================================================"
