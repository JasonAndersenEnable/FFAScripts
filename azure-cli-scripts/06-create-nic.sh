#!/usr/bin/env bash
# =============================================================================
#  06 — Create Network Interface (NIC)
#  PS1 source: New-AzNetworkInterface
#  Independent: yes — assumes Subnet, Public IP, and NSG already exist.
#               Will fail loudly with a clear message if any are missing.
#  Idempotent: skips creation if NIC already exists.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()  { printf '[OK]  %s\n' "$*"; }
err() { printf '[ERR] %s\n' "$*" >&2; exit 1; }

if az network nic show -g "${RG}" -n "${NIC_NAME}" --only-show-errors >/dev/null 2>&1; then
  ok "NIC already exists: ${NIC_NAME}"
  exit 0
fi

# Hard preconditions — fail clearly rather than producing a cryptic az error
az network vnet subnet show -g "${RG}" --vnet-name "${VNET_NAME}" -n "${SUBNET_NAME}" \
  --only-show-errors >/dev/null 2>&1 \
  || err "Subnet ${SUBNET_NAME} not found in VNet ${VNET_NAME} — run 02 first"
az network public-ip show -g "${RG}" -n "${PIP_NAME}" --only-show-errors >/dev/null 2>&1 \
  || err "Public IP ${PIP_NAME} not found — run 05 first"
az network nsg show -g "${RG}" -n "${NSG_NAME}" --only-show-errors >/dev/null 2>&1 \
  || err "NSG ${NSG_NAME} not found — run 03 first"

log "Creating NIC: ${NIC_NAME}"
# shellcheck disable=SC2086
az network nic create \
  --resource-group "${RG}" \
  --name "${NIC_NAME}" \
  --location "${LOCATION}" \
  --vnet-name "${VNET_NAME}" \
  --subnet "${SUBNET_NAME}" \
  --public-ip-address "${PIP_NAME}" \
  --network-security-group "${NSG_NAME}" \
  --tags ${TAGS} \
  --only-show-errors -o none

ok "NIC created: ${NIC_NAME}"
