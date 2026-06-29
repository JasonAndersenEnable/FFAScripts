#!/usr/bin/env bash
# =============================================================================
#  10 - Create Azure SQL Server + databases (OPTIONAL)
#  PS1 source: n/a - new step for the Azure SQL backend path.
#  Independent: yes (only requires the resource group from 01).
#  Idempotent: skips creation if server / DB already exists.
#
#  Creates:
#    - Logical SQL Server: ${SQL_SERVER_NAME}.database.windows.net
#    - Firewall rule:      AllowAzureServices  (lets in-Azure VMs connect)
#    - Databases:          ${SQL_DBS} (default: RMx_Config RMx_SampleTenant)
#
#  Note: not run by 99-deploy-all.sh - this is a separate optional step for the
#  Azure SQL backend. If you're using local SQL Express (in-VM 04-Install-Sql),
#  skip this entirely.
#
#  Cost note: S0 DBs are ~$15/mo each. To minimize cost during dev:
#      export SQL_DB_SKU=Basic         # ~$5/mo per DB, 2GB max
#      export SQL_DB_SKU=GP_S_Gen5_2   # serverless, auto-pauses, pay-per-second
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '[OK]  %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
err()  { printf '[ERR] %s\n' "$*" >&2; exit 1; }

# --- Admin password: prompt if not pre-supplied ----------------------------
if [[ -z "${SQL_ADMIN_PASSWORD:-}" ]]; then
  if [[ -t 0 ]]; then
    read -r -s -p "Enter Azure SQL admin password for ${SQL_ADMIN_USER}: " SQL_ADMIN_PASSWORD
    echo
    [[ -n "${SQL_ADMIN_PASSWORD}" ]] || err "Empty password entered"
    export SQL_ADMIN_PASSWORD
  else
    err "SQL_ADMIN_PASSWORD is empty and stdin is not a TTY. Source from Key Vault."
  fi
fi

# --- Preflight: resource group must exist -----------------------------------
az group show -n "${RG}" --only-show-errors >/dev/null 2>&1 \
  || err "Resource group ${RG} not found - run 01-create-resource-group.sh first"

# --- 1. Create the logical SQL Server (idempotent) -------------------------
if az sql server show -g "${RG}" -n "${SQL_SERVER_NAME}" --only-show-errors >/dev/null 2>&1; then
  ok "Azure SQL Server already exists: ${SQL_SERVER_NAME}"
else
  log "Creating Azure SQL Server: ${SQL_SERVER_NAME} (${LOCATION})"
  # shellcheck disable=SC2086
  az sql server create \
    --resource-group "${RG}" \
    --name "${SQL_SERVER_NAME}" \
    --location "centralus" \
    --admin-user "${SQL_ADMIN_USER}" \
    --admin-password "${SQL_ADMIN_PASSWORD}" \
    --tags ${TAGS} \
    --only-show-errors -o none
  ok "SQL Server created: ${SQL_SERVER_NAME}.database.windows.net"
fi

# --- 2. Firewall rule: allow other Azure services (incl. our VM) -----------
# The 0.0.0.0/0.0.0.0 special rule means "any Azure-internal IP".
if az sql server firewall-rule show -g "${RG}" -s "${SQL_SERVER_NAME}" \
     -n AllowAzureServices --only-show-errors >/dev/null 2>&1; then
  ok "Firewall rule AllowAzureServices already exists"
else
  log 'Creating firewall rule: AllowAzureServices'
  az sql server firewall-rule create \
    --resource-group "${RG}" \
    --server "${SQL_SERVER_NAME}" \
    --name AllowAzureServices \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    --only-show-errors -o none
  ok 'Firewall rule AllowAzureServices created'
fi

# --- 3. Create each database (idempotent) ----------------------------------
# shellcheck disable=SC2206
DB_LIST=( ${SQL_DBS} )
for db in "${DB_LIST[@]}"; do
  if az sql db show -g "${RG}" -s "${SQL_SERVER_NAME}" -n "${db}" --only-show-errors >/dev/null 2>&1; then
    ok "Database already exists: ${db}"
  else
    log "Creating database: ${db} (SKU: ${SQL_DB_SKU})"
    # shellcheck disable=SC2086
    az sql db create \
      --resource-group "${RG}" \
      --server "${SQL_SERVER_NAME}" \
      --name "${db}" \
      --service-objective "${SQL_DB_SKU}" \
      --tags ${TAGS} \
      --only-show-errors -o none
    ok "Database created: ${db}"
  fi
done

# --- 4. Print connection details for the in-VM scripts ---------------------
SERVER_FQDN="${SQL_SERVER_NAME}.database.windows.net"
echo
ok 'Azure SQL provisioned. Use these values in 08-Configure-Tenant-Json.ps1 on the VM:'
printf '  configDBServer    : %s\n' "${SERVER_FQDN}"
printf '  configDb          : %s\n' "${DB_LIST[0]}"
printf '  tenantDbServer    : %s\n' "${SERVER_FQDN}"
printf '  tenantDb          : %s\n' "${DB_LIST[1]:-${DB_LIST[0]}}"
printf '  username          : %s\n' "${SQL_ADMIN_USER}"
printf '  password          : *** masked ***\n'
echo
ok 'On the VM:'
# $env:SQL_BACKEND is a literal PowerShell variable - keep in single quotes.
# shellcheck disable=SC2016
printf '  $env:SQL_BACKEND  = "Azure"   # already the default in config.ps1\n'
printf '  ./08-Configure-Tenant-Json.ps1\n'
