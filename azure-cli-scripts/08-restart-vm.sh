#!/usr/bin/env bash
# =============================================================================
#  08 - Restart VM and wait until running
#  PS1 source: Invoke-Script06-RebootVM (Restart-AzVM + power-state polling)
#  Independent: yes. Re-runnable.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()  { printf '[OK]  %s\n' "$*"; }
err() { printf '[ERR] %s\n' "$*" >&2; exit 1; }

# shellcheck disable=SC2016 # backticks below are JMESPath literals, not shell expansion
state="$(az vm get-instance-view -g "${RG}" -n "${VM_NAME}" \
          --query 'instanceView.statuses[?starts_with(code, `PowerState`)].displayStatus' \
          -o tsv)"
[[ "${state}" == "VM running" ]] || err "VM not running (state=${state})"
ok "VM is running - initiating restart"

az vm restart -g "${RG}" -n "${VM_NAME}" --no-wait --only-show-errors -o none

log "Restart command sent - waiting for VM to come back online (timeout ${TIMEOUT_SECONDS}s)"
sleep 25

elapsed=0
while :; do
  sleep "${POLL_INTERVAL}"
  elapsed=$((elapsed + POLL_INTERVAL))
  # shellcheck disable=SC2016 # JMESPath literals
  state="$(az vm get-instance-view -g "${RG}" -n "${VM_NAME}" \
            --query 'instanceView.statuses[?starts_with(code, `PowerState`)].displayStatus' \
            -o tsv 2>/dev/null || echo 'unknown')"
  log "  state=${state}  (${elapsed}s)"
  if [[ "${state}" == "VM running" ]]; then
    ok "VM is back online"
    break
  fi
  if (( elapsed >= TIMEOUT_SECONDS )); then
    err "Timeout - VM did not return to running within ${TIMEOUT_SECONDS}s"
  fi
done

log "Sleeping 30s for services to initialise"
sleep 30
ok "Restart complete: ${VM_NAME}"
