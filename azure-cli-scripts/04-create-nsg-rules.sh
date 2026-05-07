#!/usr/bin/env bash
# =============================================================================
#  04 - Create / update NSG inbound rules
#  PS1 source: 5x New-AzNetworkSecurityRuleConfig in Script 01
#  Independent: yes (only requires the NSG to exist).
#  Idempotent: each rule uses a fixed name; re-running upserts the rule.
#
#  *** RDP TEMPORARILY OPEN TO THE INTERNET ***
#  The Allow-RDP rule below is set to source '*' so you can connect from any
#  network. Tighten it back to ${RDP_ALLOWED_CIDR} (or your specific public IP)
#  as soon as you're in. To lock it back down to your current public IP only:
#
#      MYIP=$(curl -s https://ifconfig.me)
#      az network nsg rule update -g "${RG}" --nsg-name "${NSG_NAME}" \
#          --name Allow-RDP --source-address-prefixes "${MYIP}/32"
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '[OK]  %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }

upsert_rule() {
  local name="$1" priority="$2" src="$3" ports="$4"
  log "Upserting NSG rule: ${name} (priority ${priority}, source ${src}, ports ${ports})"
  # Intentional word-splitting on ${ports}: az accepts multiple ports as separate args.
  # shellcheck disable=SC2086
  az network nsg rule create \
    --resource-group "${RG}" \
    --nsg-name "${NSG_NAME}" \
    --name "${name}" \
    --priority "${priority}" \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "${src}" \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges ${ports} \
    --only-show-errors -o none
  ok "Rule ready: ${name}"
}

upsert_rule "Allow-HTTP"     100 '*'              "80"
upsert_rule "Allow-HTTPS"    110 '*'              "443"
# FFA app ports - sourced from config.env so they stay in sync with in-VM firewall
upsert_rule "Allow-FFA-App"  120 'VirtualNetwork' "${FFA_APP_PORTS}"
upsert_rule "Allow-SQL"      130 'VirtualNetwork' "1433"

# *** RDP relaxed to Internet - tighten ASAP ***
# Was: upsert_rule "Allow-RDP"  200 "${RDP_ALLOWED_CIDR}" "3389"
upsert_rule "Allow-RDP"      200 '*' "3389"
warn "Allow-RDP is now open to the INTERNET ('*'). Lock it back down to your IP once you have access:"
warn "  MYIP=\$(curl -s https://ifconfig.me)"
warn "  az network nsg rule update -g ${RG} --nsg-name ${NSG_NAME} --name Allow-RDP --source-address-prefixes \${MYIP}/32"

ok "All NSG rules in place on ${NSG_NAME}"
