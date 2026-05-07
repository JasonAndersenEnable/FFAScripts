#!/usr/bin/env bash
# =============================================================================
#  99 — Convenience wrapper: run all Azure-resource scripts in order.
#  Comment out anything you want to skip. Each script is independently runnable.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/00-prereqs.sh"
bash "${SCRIPT_DIR}/01-create-resource-group.sh"
bash "${SCRIPT_DIR}/02-create-vnet-subnet.sh"
bash "${SCRIPT_DIR}/03-create-nsg.sh"
bash "${SCRIPT_DIR}/04-create-nsg-rules.sh"
bash "${SCRIPT_DIR}/05-create-public-ip.sh"
bash "${SCRIPT_DIR}/06-create-nic.sh"
bash "${SCRIPT_DIR}/07-create-vm.sh"
# 08 + 09 only after in-VM configuration scripts (PS) have been pushed via run-command:
# bash "${SCRIPT_DIR}/08-restart-vm.sh"
# bash "${SCRIPT_DIR}/09-verify-vm.sh"

echo "[OK]  All Azure resources provisioned."
