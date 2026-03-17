#!/bin/sh

SLURM_FILE="/etc/routinator/slurm.json"

echo "[RPKI] Step 1/2 -- Initializing Routinator (accepting ARIN RPA and installing TALs)..."

# routinator MUST be initialized before the server can start.
# Exit code 2 without init = "ARIN Relying Party Agreement not accepted".
# --accept-arin-rpa accepts the agreement non-interactively.
if routinator init --accept-arin-rpa 2>&1; then
    echo "[RPKI] Init succeeded."
elif routinator init 2>&1; then
    echo "[RPKI] Init succeeded (without ARIN flag)."
else
    echo "[RPKI] Init failed -- continuing anyway (may already be initialized)."
fi

echo "[RPKI] Step 2/2 -- Starting RTR server on 0.0.0.0:3323 and HTTP on 0.0.0.0:9556..."
echo "[RPKI] Using SLURM exceptions: ${SLURM_FILE}"

# Try --exceptions (standard flag across most routinator versions)
if routinator server \
    --rtr 0.0.0.0:3323 \
    --http 0.0.0.0:9556 \
    --exceptions "$SLURM_FILE" \
    --refresh 300 \
    --retry 300 \
    --expire 7200; then
    exit 0
fi

# Fallback: without HTTP (some older builds don't have --http)
if routinator server \
    --rtr 0.0.0.0:3323 \
    --exceptions "$SLURM_FILE" \
    --refresh 300 \
    --retry 300 \
    --expire 7200; then
    exit 0
fi

# Last resort: no SLURM exceptions, bare server
if routinator server --rtr 0.0.0.0:3323 --http 0.0.0.0:9556; then
    echo "[RPKI] WARNING: Started without SLURM file -- local VRPs not loaded."
    exit 0
fi

echo "[RPKI] All startup attempts failed."
echo "[RPKI] Run: docker logs clab-bgp-hijack-rpki-rpki"
exit 1
