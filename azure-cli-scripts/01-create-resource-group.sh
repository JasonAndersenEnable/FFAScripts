#!/usr/bin/env bash
# =============================================================================
#  01 — Create Resource Group
#  PS1 source: Invoke-Script01-ProvisionVM (New-AzResourceGroup)
#  Independent: yes. Re-runnable: yes (az group create is idempotent).
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()  { printf '[OK]  %s\n' "$*"; }

log "Ensuring resource group: ${RG} (${LOCATION})"
# shellcheck disable=SC2086
az group create \
  --name "${RG}" \
  --location "${LOCATION}" \
  --tags ${TAGS} \
  --only-show-errors -o table

ok "Resource group ready: ${RG}"
