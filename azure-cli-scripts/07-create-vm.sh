#!/usr/bin/env bash
# =============================================================================
#  07 - Create Windows Server VM
#  PS1 source: New-AzVMConfig | Set-AzVMOperatingSystem | Set-AzVMSourceImage |
#              Add-AzVMNetworkInterface | Set-AzVMOSDisk | New-AzVM
#  Independent: yes - uses the existing NIC from 06.
#  Idempotent: skips creation if the VM already exists.
#
#  Interactive prompts:
#  - VM_SIZE     : if empty, prompts with 4-tier menu
#  - VM_ADMIN_PASSWORD : if empty, read -s prompt (echo suppressed)
#  Set either env var beforehand to skip its prompt (pipeline use).
#
#  Note: VM_NAME is the Azure resource name (any length).
#        VM_COMPUTER_NAME is the Windows OS hostname (max 15 chars).
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()  { printf '[OK]  %s\n' "$*"; }
err() { printf '[ERR] %s\n' "$*" >&2; exit 1; }

# Hard validation: Windows 15-char hostname limit
if [[ ${#VM_COMPUTER_NAME} -gt 15 ]]; then
    err "VM_COMPUTER_NAME='${VM_COMPUTER_NAME}' is ${#VM_COMPUTER_NAME} chars - max 15 for Windows."
fi

# ---- VM SKU prompt -----------------------------------------------------------
prompt_vm_size() {
  cat <<'MENU'

Select VM SKU:
  1) Cheapest         - Standard_B4ms     (4 vCPU, 16 GiB, burstable)    ~$120/mo
  2) **Default** - Stable but cheap - Standard_D4s_v5   (4 vCPU, 16 GiB, general)      ~$140/mo
  3) More expensive   - Standard_E4s_v5   (4 vCPU, 32 GiB, mem-opt)      ~$150/mo
  4) Production       - Standard_E8s_v5   (8 vCPU, 64 GiB, mem-opt)      ~$300/mo  [needs >4-core quota]

MENU
  local choice
  read -r -p "Choice [1-4, default 1]: " choice
  case "${choice:-1}" in
    1) VM_SIZE=Standard_B4ms    ;;
    2) VM_SIZE=Standard_D4s_v5  ;;
    3) VM_SIZE=Standard_E4s_v5  ;;
    4) VM_SIZE=Standard_E8s_v5  ;;
    *) err "Invalid choice: ${choice}" ;;
  esac
  export VM_SIZE
  ok "Selected SKU: ${VM_SIZE}"
}

if [[ -z "${VM_SIZE:-}" ]]; then
  if [[ -t 0 ]]; then
    prompt_vm_size
  else
    err "VM_SIZE is empty and stdin is not a TTY. Set VM_SIZE before running in a pipeline."
  fi
fi

# ---- Admin password prompt --------------------------------------------------
if [[ -z "${VM_ADMIN_PASSWORD:-}" ]]; then
  if [[ -t 0 ]]; then
    read -r -s -p "Enter VM admin password for ${VM_ADMIN_USERNAME}: " VM_ADMIN_PASSWORD
    echo
    [[ -n "${VM_ADMIN_PASSWORD}" ]] || err "Empty password entered"
    export VM_ADMIN_PASSWORD
  else
    err "VM_ADMIN_PASSWORD is empty and stdin is not a TTY. Source from Key Vault."
  fi
fi

# ---- Provisioning -----------------------------------------------------------
if az vm show -g "${RG}" -n "${VM_NAME}" --only-show-errors >/dev/null 2>&1; then
  ok "VM already exists: ${VM_NAME}"
  exit 0
fi

az network nic show -g "${RG}" -n "${NIC_NAME}" --only-show-errors >/dev/null 2>&1 \
  || err "NIC ${NIC_NAME} not found - run 06 first"

log "Creating VM: ${VM_NAME} (computer-name=${VM_COMPUTER_NAME}, ${VM_SIZE}, ${VM_IMAGE})"
# shellcheck disable=SC2086
az vm create \
  --resource-group "${RG}" \
  --name "${VM_NAME}" \
  --computer-name "${VM_COMPUTER_NAME}" \
  --location "${LOCATION}" \
  --size "${VM_SIZE}" \
  --image "${VM_IMAGE}" \
  --admin-username "${VM_ADMIN_USERNAME}" \
  --admin-password "${VM_ADMIN_PASSWORD}" \
  --nics "${NIC_NAME}" \
  --os-disk-name "${VM_OS_DISK_NAME}" \
  --os-disk-size-gb "${VM_OS_DISK_SIZE_GB}" \
  --storage-sku "${VM_OS_DISK_SKU}" \
  --enable-auto-update true \
  --tags ${TAGS} \
  --only-show-errors -o table

ok "VM created: ${VM_NAME} (hostname ${VM_COMPUTER_NAME})"
