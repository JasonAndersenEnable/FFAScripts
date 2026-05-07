#!/usr/bin/env bash
# =============================================================================
#  00 — Prerequisites & login check
#  Verifies az CLI presence, login state, and target subscription.
#  Idempotent. Safe to source or run repeatedly.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '[OK]  %s\n' "$*"; }
err()  { printf '[ERR] %s\n' "$*" >&2; exit 1; }

command -v az >/dev/null 2>&1 || err "az CLI not found on PATH"

if ! az account show >/dev/null 2>&1; then
  log "Not logged in — running 'az login'"
  az login --only-show-errors >/dev/null
fi

if ! az account set --subscription "${SUBSCRIPTION_ID}" >/dev/null 2>&1; then
  log "Subscription '${SUBSCRIPTION_ID}' not found. Please enter a valid subscription id or name:"
  read -r -p "Subscription: " SUBSCRIPTION_ID
  az account set --subscription "${SUBSCRIPTION_ID}"
fi
ok "Active subscription: $(az account show --query name -o tsv)"
ok "Region: ${LOCATION}"
