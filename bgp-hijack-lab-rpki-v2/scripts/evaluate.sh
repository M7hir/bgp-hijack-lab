#!/bin/bash
# =============================================================
# evaluate.sh — BGP Hijack Lab Evaluation Script
#
# Measures and logs timing metrics for:
#   1. Attack propagation time (injection → route change)
#   2. Mitigation effectiveness (filter → hijack blocked)
#   3. Recovery time (withdrawal → legitimate restored)
#   4. Hijack success rate (with and without mitigation)
#
# Output: evaluation_<timestamp>.log + evaluation_<timestamp>.csv
# =============================================================

LAB="bgp-hijack-rpki"
R1="clab-${LAB}-r1"; R2="clab-${LAB}-r2"
R3="clab-${LAB}-r3"; R4="clab-${LAB}-r4"
MITIGATION_TARGET="${1:-all}"

if [ "$MITIGATION_TARGET" != "r1" ] && [ "$MITIGATION_TARGET" != "all" ]; then
  echo "Usage: $0 [r1|all]"
  echo "  r1  = partial deployment (R1 only)"
  echo "  all = full deployment (R1 + R2)"
  exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="evaluation_${TIMESTAMP}.log"
CSV="evaluation_${TIMESTAMP}.csv"

BOLD="\033[1m"; RED="\033[31m"; GREEN="\033[32m"
YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

# ── Helpers ───────────────────────────────────────────────────
log() {
  echo -e "$*"
  echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG"
}

run_r1() { docker exec "$R1" vtysh -c "$1" 2>/dev/null; }
run_r4() { docker exec "$R4" vtysh -c "$1" 2>/dev/null; }

# Check if R1 currently has AS400 as best path for victim prefix
is_hijacked() {
  run_r1 "show bgp ipv4 unicast 13.0.0.0/24" | grep -q "400" && \
  run_r1 "show ip route 13.0.0.0/24" | grep -q "10.14.0.2"
}

# Check if R1 has legitimate path as best
is_legitimate() {
  run_r1 "show ip route 13.0.0.0/24" | grep -q "10.12.0.2"
}

# Poll until condition is true, return elapsed seconds
# Usage: wait_for_condition <function> <max_seconds>
wait_for_condition() {
  local condition=$1
  local max=$2
  local elapsed=0
  while [ $elapsed -lt $max ]; do
    if $condition; then
      echo $elapsed
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo "TIMEOUT"
  return 1
}

inject_attack() {
  docker exec "$R4" vtysh \
    -c "configure terminal" \
    -c "router bgp 400" \
    -c "network 13.0.0.0/24" \
    -c "end" 2>/dev/null
  docker exec "$R4" ip route add blackhole 13.0.0.0/24 2>/dev/null || true
}

withdraw_attack() {
  docker exec "$R4" vtysh \
    -c "configure terminal" \
    -c "router bgp 400" \
    -c "no network 13.0.0.0/24" \
    -c "end" 2>/dev/null
  docker exec "$R4" ip route del blackhole 13.0.0.0/24 2>/dev/null || true
  docker exec "$R4" ip route del 13.0.0.0/24 2>/dev/null || true
}

apply_mitigation() {
  "$(dirname "$0")/apply_mitigation.sh" "$MITIGATION_TARGET" >/dev/null
}

remove_mitigation() {
  "$(dirname "$0")/remove_mitigation.sh" all >/dev/null
}

# ── CSV Header ────────────────────────────────────────────────
echo "Test,Metric,Value,Unit" > "$CSV"

record() {
  local test=$1 metric=$2 value=$3 unit=$4
  echo "$test,$metric,$value,$unit" >> "$CSV"
}

# ─────────────────────────────────────────────────────────────
log "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
log "${BOLD}║     BGP Hijack Lab — Evaluation & Measurement    ║${RESET}"
log "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
log "Timestamp: $(date)"
log "Log file:  $LOG"
log "CSV file:  $CSV"
log "Mitigation target: $MITIGATION_TARGET"
log ""
record "Config" "mitigation_target" "$MITIGATION_TARGET" "string"

# ─────────────────────────────────────────────────────────────
log "${BOLD}━━━  Phase 1: Baseline Verification  ━━━${RESET}"
# ─────────────────────────────────────────────────────────────
log "Verifying clean baseline before tests..."

if is_legitimate; then
  log "${GREEN}[OK] Baseline: 13.0.0.0/24 via legitimate path (AS200 AS300)${RESET}"
  record "Baseline" "legitimate_path_present" "true" "boolean"
else
  log "${RED}[WARN] Baseline not clean — withdrawing any existing attack${RESET}"
  withdraw_attack
  sleep 10
fi

# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}━━━  Phase 2: Attack Propagation Time (3 runs)  ━━━${RESET}"
# ─────────────────────────────────────────────────────────────
log "Measuring how long BGP takes to propagate hijack from R4 to R1"
log ""

PROPAGATION_TIMES=()

for run in 1 2 3; do
  log "${CYAN}Run $run/3 — Injecting exact prefix hijack...${RESET}"

  START=$(date +%s)
  inject_attack
  ELAPSED=$(wait_for_condition is_hijacked 60)

  if [ "$ELAPSED" = "TIMEOUT" ]; then
    log "${RED}Run $run: TIMEOUT — hijack did not propagate within 60s${RESET}"
    record "Attack_Propagation" "run_${run}_seconds" "TIMEOUT" "seconds"
  else
    log "${GREEN}Run $run: Hijack propagated in ${ELAPSED}s${RESET}"
    PROPAGATION_TIMES+=($ELAPSED)
    record "Attack_Propagation" "run_${run}_seconds" "$ELAPSED" "seconds"
  fi

  # Capture route table at hijack point
  log "R1 routing table at hijack point (Run $run):"
  run_r1 "show ip route 13.0.0.0/24" >> "$LOG"

  log "${YELLOW}Withdrawing attack for next run...${RESET}"
  withdraw_attack
  sleep 15
done

# Calculate average propagation time
if [ ${#PROPAGATION_TIMES[@]} -gt 0 ]; then
  TOTAL=0
  for t in "${PROPAGATION_TIMES[@]}"; do TOTAL=$((TOTAL + t)); done
  AVG=$((TOTAL / ${#PROPAGATION_TIMES[@]}))
  log "${GREEN}Average attack propagation time: ${AVG}s${RESET}"
  record "Attack_Propagation" "average_seconds" "$AVG" "seconds"
  record "Attack_Propagation" "runs_completed" "${#PROPAGATION_TIMES[@]}" "count"
fi

# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}━━━  Phase 3: Recovery Time After Withdrawal (3 runs)  ━━━${RESET}"
# ─────────────────────────────────────────────────────────────
log "Measuring how long BGP takes to restore legitimate path after attack stops"
log ""

RECOVERY_TIMES=()

for run in 1 2 3; do
  log "${CYAN}Run $run/3 — Injecting attack then withdrawing...${RESET}"

  inject_attack
  sleep 15  # let hijack fully establish

  if ! is_hijacked; then
    log "${RED}Run $run: Hijack did not establish — skipping${RESET}"
    continue
  fi

  log "Hijack confirmed. Withdrawing now..."
  START=$(date +%s)
  withdraw_attack
  ELAPSED=$(wait_for_condition is_legitimate 60)

  if [ "$ELAPSED" = "TIMEOUT" ]; then
    log "${RED}Run $run: TIMEOUT — legitimate path not restored within 60s${RESET}"
    record "Recovery_Time" "run_${run}_seconds" "TIMEOUT" "seconds"
  else
    log "${GREEN}Run $run: Legitimate path restored in ${ELAPSED}s${RESET}"
    RECOVERY_TIMES+=($ELAPSED)
    record "Recovery_Time" "run_${run}_seconds" "$ELAPSED" "seconds"
  fi

  sleep 10
done

if [ ${#RECOVERY_TIMES[@]} -gt 0 ]; then
  TOTAL=0
  for t in "${RECOVERY_TIMES[@]}"; do TOTAL=$((TOTAL + t)); done
  AVG=$((TOTAL / ${#RECOVERY_TIMES[@]}))
  log "${GREEN}Average recovery time: ${AVG}s${RESET}"
  record "Recovery_Time" "average_seconds" "$AVG" "seconds"
fi

# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}━━━  Phase 4: Mitigation Effectiveness  ━━━${RESET}"
# ─────────────────────────────────────────────────────────────
log "Testing hijack success rate WITH and WITHOUT validator-backed ROV"
log ""

ATTEMPTS=5
SUCCESS_NO_MIT=0
SUCCESS_WITH_MIT=0

# Test WITHOUT mitigation
log "${CYAN}Testing $ATTEMPTS attempts WITHOUT mitigation...${RESET}"
remove_mitigation
sleep 5

for i in $(seq 1 $ATTEMPTS); do
  inject_attack
  sleep 12
  if is_hijacked; then
    SUCCESS_NO_MIT=$((SUCCESS_NO_MIT + 1))
    log "  Attempt $i: ${RED}HIJACKED${RESET}"
  else
    log "  Attempt $i: ${GREEN}LEGITIMATE${RESET}"
  fi
  withdraw_attack
  sleep 10
done

RATE_NO_MIT=$(echo "scale=0; $SUCCESS_NO_MIT * 100 / $ATTEMPTS" | bc)
log "${RED}Hijack success rate WITHOUT mitigation: ${RATE_NO_MIT}% (${SUCCESS_NO_MIT}/${ATTEMPTS})${RESET}"
record "Effectiveness" "hijack_rate_no_mitigation_pct" "$RATE_NO_MIT" "percent"
record "Effectiveness" "hijacks_without_mitigation" "$SUCCESS_NO_MIT" "count"

# Test WITH mitigation
log ""
log "${CYAN}Testing $ATTEMPTS attempts WITH mitigation applied (${MITIGATION_TARGET})...${RESET}"
apply_mitigation
sleep 5

for i in $(seq 1 $ATTEMPTS); do
  inject_attack
  sleep 12
  if is_hijacked; then
    SUCCESS_WITH_MIT=$((SUCCESS_WITH_MIT + 1))
    log "  Attempt $i: ${RED}HIJACKED (mitigation failed)${RESET}"
  else
    log "  Attempt $i: ${GREEN}BLOCKED (mitigation succeeded)${RESET}"
  fi
  withdraw_attack
  sleep 10
done

RATE_WITH_MIT=$(echo "scale=0; $SUCCESS_WITH_MIT * 100 / $ATTEMPTS" | bc)
BLOCK_RATE=$((100 - RATE_WITH_MIT))
log "${GREEN}Hijack success rate WITH mitigation: ${RATE_WITH_MIT}% (${SUCCESS_WITH_MIT}/${ATTEMPTS})${RESET}"
log "${GREEN}Mitigation block rate: ${BLOCK_RATE}%${RESET}"
record "Effectiveness" "hijack_rate_with_mitigation_pct" "$RATE_WITH_MIT" "percent"
record "Effectiveness" "mitigation_block_rate_pct" "$BLOCK_RATE" "percent"
record "Effectiveness" "hijacks_with_mitigation" "$SUCCESS_WITH_MIT" "count"

# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}━━━  Phase 5: Mitigation Application Time  ━━━${RESET}"
# ─────────────────────────────────────────────────────────────
log "Measuring how long mitigation takes to block an active hijack"
log ""

# First inject attack, then apply mitigation, measure time to block
inject_attack
sleep 15

if is_hijacked; then
  log "Active hijack confirmed. Applying mitigation now..."
  remove_mitigation
  sleep 3

  MIT_START=$(date +%s)
  apply_mitigation

  # Poll until hijack is blocked
  ELAPSED=0
  while [ $ELAPSED -lt 30 ]; do
    if ! is_hijacked; then
      break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
  done

  if ! is_hijacked; then
    log "${GREEN}Mitigation blocked active hijack in ${ELAPSED}s${RESET}"
    record "Mitigation_Speed" "time_to_block_active_hijack_seconds" "$ELAPSED" "seconds"
  else
    log "${RED}TIMEOUT: Mitigation did not block hijack within 30s${RESET}"
    record "Mitigation_Speed" "time_to_block_active_hijack_seconds" "TIMEOUT" "seconds"
  fi
else
  log "${YELLOW}Hijack did not establish — skipping mitigation speed test${RESET}"
fi

withdraw_attack
remove_mitigation
sleep 10

# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}━━━  Evaluation Summary  ━━━${RESET}"
# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}┌─────────────────────────────────────────────────────┐${RESET}"
log "${BOLD}│              RESULTS SUMMARY                        │${RESET}"
log "${BOLD}├─────────────────────────────────────────────────────┤${RESET}"

if [ ${#PROPAGATION_TIMES[@]} -gt 0 ]; then
  TOTAL=0
  for t in "${PROPAGATION_TIMES[@]}"; do TOTAL=$((TOTAL + t)); done
  AVG_PROP=$((TOTAL / ${#PROPAGATION_TIMES[@]}))
  log "│ Avg attack propagation time:    ${AVG_PROP}s                     │"
fi

if [ ${#RECOVERY_TIMES[@]} -gt 0 ]; then
  TOTAL=0
  for t in "${RECOVERY_TIMES[@]}"; do TOTAL=$((TOTAL + t)); done
  AVG_REC=$((TOTAL / ${#RECOVERY_TIMES[@]}))
  log "│ Avg recovery time after attack: ${AVG_REC}s                     │"
fi

log "│ Hijack success (no mitigation): ${RATE_NO_MIT}%                   │"
log "│ Hijack success (with RPKI-ROV ${MITIGATION_TARGET}): ${RATE_WITH_MIT}%           │"
log "│ Mitigation block rate:          ${BLOCK_RATE}%                  │"
log "${BOLD}└─────────────────────────────────────────────────────┘${RESET}"
log ""
log "Full log:  $LOG"
log "CSV data:  $CSV"
log ""
log "${CYAN}The CSV file can be opened in Excel/LibreOffice for charts.${RESET}"
log "${BOLD}================================================${RESET}"
