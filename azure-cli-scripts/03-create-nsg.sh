#!/usr/bin/env bash
# =============================================================================
#  03 — Create Network Security Group (empty)
#  PS1 source: New-AzNetworkSecurityGroup (rules split out into 04)
#  Independent: yes. Idempotent.
#  NOTE: Rule creation is intentionally separated into 04-create-nsg-rules.sh
#        so rules can be added/edited without recreating the NSG.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()  { printf '[OK]  %s\n' "$*"; }

if az network nsg show -g "${RG}" -n "${NSG_NAME}" --only-show-errors >/dev/null 2>&1; then
  ok "NSG already exists: ${NSG_NAME}"
  exit 0
fi

log "Creating NSG: ${NSG_NAME}"
# shellcheck disable=SC2086
az network nsg create \
  --resource-group "${RG}" \
  --name "${NSG_NAME}" \
  --location "${LOCATION}" \
  --tags ${TAGS} \
  --only-show-errors -o none

ok "NSG created: ${NSG_NAME}"
