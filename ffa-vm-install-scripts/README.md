# FFA In-VM Install Scripts

These scripts run **inside the Windows VM** as **Local Administrator**. They take the bare Windows Server VM that the Azure CLI scripts provisioned and turn it into an FFA host.

## Layout (post-restructure)

Linear numbering, one concern per file. No `a/b/c` suffixes.

| File | Lines | Purpose | Interactive? |
|---|---|---|---|
| `config.ps1` | ~100 | Shared config + helpers | n/a |
| `01-Configure-IIS.ps1` | ~45 | Install IIS + base firewall rules (HTTP/HTTPS, FFA app ports, SQL) | no |
| `02-Install-DotNet.ps1` | ~150 | .NET runtime + ASP.NET Core runtime + Hosting Bundle + ANCM force-copy + iisreset | no |
| `03-Install-UrlRewrite.ps1` | ~40 | IIS URL Rewrite 2.1 + iisreset | no |
| `04-Install-Tools.ps1` | ~160 | Install SQL Server Management Studio and Visual Studio Code | no |
| `05-Verify-Prerequisites.ps1` | ~70 | Read-only health check across IIS, .NET, ANCM, URL Rewrite, SQL | no |
| `06-Import-SSL-Certificate.ps1` | ~40 | Import CA-signed PFX into LocalMachine\My | yes (params) |
| `07-Download-Installer.ps1` | ~95 | Pull installer.zip from FFA repo, rename Installation.{VmName}.json | yes (path) |
| `08-Configure-Tenant-Json.ps1` | ~120 | Set every key in Installation JSON. Interactive prompts OR all-params via `-NonInteractive` | yes (default) |
| `09-Setup-Binaries.ps1` | ~150 | Extract ManualInstallationTools, rename Version Template, overlay pipeline drop, fetch Config DacPac if missing | yes (paths) |
| `10-Run-PreInstall.ps1` | ~45 | Run the Flintfox pre-install scripts in order (PreInstall-* + 00-StopApplications + 01-DeployConfigDb) | no |
| `11-Install-FFA.ps1` | ~30 | Invoke `InstallFFA.ps1` from the ManualInstallationScripts folder | no |
| `99-Run-All.ps1` | ~25 | Auto-runs 01-05 (no-prompt OS prep). Lists 06-11 to run individually. | n/a |

### Deprecated stubs

These files are kept so older docs / muscle memory don't 404. Each prints a redirect message and exits with code 1.

```
02-Configure-IIS-Firewall.ps1     -> 01-Configure-IIS.ps1
03-Install-Prerequisites.ps1      -> 02 / 03 / 04
03a-Install-DotNet.ps1            -> 02-Install-DotNet.ps1
03b-Install-UrlRewrite.ps1        -> 03-Install-UrlRewrite.ps1
03c-Install-Sql.ps1               -> 04-Install-Tools.ps1
04-Configure-FFA-Ports.ps1        -> 01-Configure-IIS.ps1 (firewall logic merged in)
05-Import-SSL-Certificate.ps1     -> 06-Import-SSL-Certificate.ps1
07-Download-Prepare-FFA.ps1       -> 07 / 08 / 09 / 10 / 11
08-Populate-Config.ps1            -> 08-Configure-Tenant-Json.ps1
```

## Run order on a fresh VM

```powershell
cd C:\path\where\you\copied\the\scripts

# Auto-runs 01-05 (no prompts)
.\99-Run-All.ps1

# Optional: only if you have a CA-signed PFX for the FFA portal
.\06-Import-SSL-Certificate.ps1 -PfxPath C:\certs\flintfox.pfx -PfxPassword '...'

# Mandatory FFA prep (interactive walkthrough)
.\07-Download-Installer.ps1
.\08-Configure-Tenant-Json.ps1
.\09-Setup-Binaries.ps1
.\10-Run-PreInstall.ps1
.\11-Install-FFA.ps1
```

## Configuration overrides

All overrides go through env vars or script parameters — never edit `config.ps1` directly.

```powershell
# Pin a different .NET 8 patch
$env:DOTNET_TARGET_VERSION = '8.0.18'

# Skip the SQL backend prompt
$env:SQL_BACKEND = 'Local'    # or 'Azure'
$env:SQL_SA_PASSWORD = (az keyvault secret show --vault-name kv-... --name sql-sa --query value -o tsv)

# Move the install root somewhere else
$env:FFA_INSTALL_ROOT = 'D:\FFA'

# Override the FFA installer scripts URL (e.g. SAS URL from Flintfox)
$env:FFA_SCRIPTS_URL = 'https://...?sv=...&sig=...'
```

Pre-supplied paths to skip the prompts in 07/09:

```powershell
.\07-Download-Installer.ps1 -InstallerZipPath C:\Users\azureadmin\Downloads\installer.zip
.\09-Setup-Binaries.ps1     -BinariesZipPath  C:\Users\azureadmin\Downloads\drop.zip
```

CI/non-interactive use of 08:

```powershell
.\08-Configure-Tenant-Json.ps1 -NonInteractive `
    -ConfigDbServer    "$env:COMPUTERNAME\SQLEXPRESS" `
    -ConfigDb          'RMx_Config' `
    -TenantDbServer    "$env:COMPUTERNAME\SQLEXPRESS" `
    -TenantDb          'RMx_Training' `
    -SqlUsername       'sa' `
    -SqlPassword       (Read-Host AsSecureString) `
    -TenantUniqueName  'central-az-supply' `
    -DatabaseVersion   '8.0.16'
```

## What you must supply yourself

| Item | Why | Where to get it |
|---|---|---|
| `installer.zip` | 07 needs it | Download from `https://flintfox.visualstudio.com/_git/FFA` master branch, `installer/` folder, three-dots menu → Download as ZIP |
| Pipeline drop ZIP | 09 needs it | Azure DevOps Pipelines, filter `all-in-one`, master-branch run → Related → drop |
| Config DacPac (sometimes) | 09 §4 fallback | Azure DevOps Pipelines, filter `db-dacpac`, `build-config-db-dacpac`, master-branch run → Related → drop |
| RMx Config + Training DB backups | InstallFFA.ps1 step 01 needs them | Email from Flintfox NZ team |
| Tenant unique name | 08 prompts for it | Decide a slug-style string per env (e.g. `central-az-supply`, `gcg`, `cona`) |
| PFX certificate (optional) | 06 imports it | Your CA |

## Idempotency

Each script detects whether its work is already done and skips:

- 01: `Get-WindowsFeature Web-Server` already Installed → skip
- 02: per-component `dotnet --list-runtimes` matching the target version → skip
- 03: `Get-WebGlobalModule RewriteModule` exists → skip
- 04: `MSSQL$<instance>` service exists → skip
- 05: read-only — always runs
- 06: re-import is harmless
- 07: `ManualInstallationScripts\Installation.*.json` already exists → skip
- 08: always runs (lets you tweak values)
- 09: per-section detection (folders populated → skip)
- 10: each pre-install script is itself idempotent (firewall rules use fixed names, etc.)
- 11: re-running `InstallFFA.ps1` is supported

Re-running `99-Run-All.ps1` after a partial completion picks up where it left off.
