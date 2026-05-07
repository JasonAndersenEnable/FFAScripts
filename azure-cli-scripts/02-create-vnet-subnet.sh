#!/usr/bin/env bash
# =============================================================================
#  02 — Create Virtual Network and Subnet
#  PS1 source: New-AzVirtualNetworkSubnetConfig + New-AzVirtualNetwork
#  Independent: yes. Idempotent: skips creation if VNet already exists,
#               then ensures the subnet exists.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()  { printf '[OK]  %s\n' "$*"; }

if az network vnet show -g "${RG}" -n "${VNET_NAME}" --only-show-errors >/dev/null 2>&1; then
  ok "VNet already exists: ${VNET_NAME}"
else
  log "Creating VNet: ${VNET_NAME} (${VNET_PREFIX})"
  # shellcheck disable=SC2086
  az network vnet create \
    --resource-group "${RG}" \
    --name "${VNET_NAME}" \
    --location "${LOCATION}" \
    --address-prefixes "${VNET_PREFIX}" \
    --tags ${TAGS} \
    --only-show-errors -o none
  ok "VNet created: ${VNET_NAME}"
fi

if az network vnet subnet show -g "${RG}" --vnet-name "${VNET_NAME}" -n "${SUBNET_NAME}" \
     --only-show-errors >/dev/null 2>&1; then
  ok "Subnet already exists: ${SUBNET_NAME}"
else
  log "Creating subnet: ${SUBNET_NAME} (${SUBNET_PREFIX})"
  az network vnet subnet create \
    --resource-group "${RG}" \
    --vnet-name "${VNET_NAME}" \
    --name "${SUBNET_NAME}" \
    --address-prefixes "${SUBNET_PREFIX}" \
    --only-show-errors -o none
  ok "Subnet created: ${SUBNET_NAME}"
fi
