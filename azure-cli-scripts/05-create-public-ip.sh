#!/usr/bin/env bash
# =============================================================================
#  05 — Create Public IP (Standard, Static)
#  PS1 source: New-AzPublicIpAddress
#  Independent: yes. Idempotent.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()  { printf '[OK]  %s\n' "$*"; }

if az network public-ip show -g "${RG}" -n "${PIP_NAME}" --only-show-errors >/dev/null 2>&1; then
  ok "Public IP already exists: ${PIP_NAME}"
  exit 0
fi

log "Creating Public IP: ${PIP_NAME} (Standard, Static)"
# shellcheck disable=SC2086
az network public-ip create \
  --resource-group "${RG}" \
  --name "${PIP_NAME}" \
  --location "${LOCATION}" \
  --sku Standard \
  --allocation-method Static \
  --tags ${TAGS} \
  --only-show-errors -o none

PIP_ADDR="$(az network public-ip show -g "${RG}" -n "${PIP_NAME}" --query ipAddress -o tsv)"
ok "Public IP created: ${PIP_NAME} (${PIP_ADDR})"
