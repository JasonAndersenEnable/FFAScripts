#!/usr/bin/env bash
# =============================================================================
#  09 — Verify VM via az vm run-command (post-reboot service checks)
#  PS1 source: Get-AzVMRunCommand checks at the end of Invoke-Script06-RebootVM
#  Independent: yes. Read-only — safe to run any time.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

run_remote() {
  local label="$1" script="$2"
  log "Check: ${label}"
  az vm run-command invoke \
    --resource-group "${RG}" \
    --name "${VM_NAME}" \
    --command-id RunPowerShellScript \
    --scripts "${script}" \
    --query 'value[0].message' -o tsv
  echo
}

run_remote "IIS (W3SVC) running"  '(Get-Service W3SVC).Status'
run_remote ".NET runtime version" 'dotnet --version'
run_remote "ANCM v2 present"      "Test-Path 'C:\\Windows\\System32\\inetsrv\\aspnetcorev2.dll'"
run_remote "URL Rewrite present"  "(Get-WebConfiguration 'system.webServer/globalModules/*' | Where-Object Name -eq 'RewriteModule') -ne \$null"

log "Verification complete for ${VM_NAME}"
