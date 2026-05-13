# =============================================================================
#  08 - Configure Installation.{VmName}.json
#  Two modes:
#    A) No parameters provided  -> interactive prompt for each key
#    B) All parameters provided -> non-interactive (CI / automation)
#  Subsumes both the old 08-Populate-Config.ps1 and section 3 of the old 07.
# =============================================================================
[CmdletBinding()]
param(
    [string] $VmName              = $env:COMPUTERNAME,

    # Optional explicit values - if omitted, the script prompts
    [string] $ConfigDbServer,
    [string] $ConfigDb,
    [string] $TenantDbServer,
    [string] $TenantDb,
    [string] $SqlUsername,
    [string] $SqlPassword,
    [string] $FfaVersion,
    [string] $TenantUniqueName,
    [string] $DatabaseVersion,
    [string] $PlatformWebRoot,
    [string] $OdataWebRoot,
    [string] $PlatformServiceRoot,

    # Set this to skip prompting and require all values via params
    [switch] $NonInteractive
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin

if ([string]::IsNullOrEmpty($FfaVersion)) { $FfaVersion = $Cfg.FfaVersion }

# JSON lives at $Cfg.InstallRoot per the FFA repo layout, but older bundles
# put it inside ManualInstallationScripts\. Try both.
$candidatePaths = @(
    (Join-Path $Cfg.InstallRoot                                         "Installation.$VmName.json"),
    (Join-Path (Join-Path $Cfg.InstallRoot 'ManualInstallationScripts') "Installation.$VmName.json")
)
$targetJsonPath = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $targetJsonPath) {
    Write-Err "Installation.$VmName.json not found in $($candidatePaths -join ' or ') - run 07-Download-Installer.ps1 first"
}

$config = Get-Content $targetJsonPath -Raw | ConvertFrom-Json

function Set-Value {
    param(
        [Parameter(Mandatory)][string]$Key,
        [string]$ParamValue,
        [Parameter(Mandatory)][string]$Description,
        [string]$Default,
        [switch]$Secret
    )
    # If a parameter value was passed, use it directly
    if (-not [string]::IsNullOrEmpty($ParamValue)) {
        $config | Add-Member -NotePropertyName $Key -NotePropertyValue $ParamValue -Force
        $shown = if ($Secret) { '*** (hidden) ***' } else { $ParamValue }
        Write-Ok "  $Key = $shown"
        return
    }
    # Param missing
    if ($NonInteractive) {
        Write-Err "$Key is required in -NonInteractive mode (param missing)"
    }
    # Interactive prompt
    $current = $null
    if ($config.PSObject.Properties.Name -contains $Key) { $current = $config.$Key }

    # Strip JSON template placeholder wrapper, e.g. <default C:\some\path>
    if ($current -match '^\<default (.+)\>$') { $current = $matches[1] }

    if ([string]::IsNullOrEmpty($current) -and $Default) { $current = $Default }
    Write-Host ''
    Write-Host "  $Key" -ForegroundColor Cyan
    Write-Host "    $Description"
    if ($Secret -and -not [string]::IsNullOrEmpty($current)) {
        Write-Host '    Current: *** (hidden) ***'
    } else {
        Write-Host "    Current: $current"
    }
    if ($Secret) {
        $secure = Read-Host '    New value (Enter to keep current)' -AsSecureString
        $new = [System.Net.NetworkCredential]::new('', $secure).Password
    } else {
        $new = Read-Host '    New value (Enter to keep current)'
    }
    if (-not [string]::IsNullOrEmpty($new)) {
        $config | Add-Member -NotePropertyName $Key -NotePropertyValue $new -Force
    } elseif (-not [string]::IsNullOrEmpty($current)) {
        $config | Add-Member -NotePropertyName $Key -NotePropertyValue $current -Force
    }
}

$defaultSqlServer = "$VmName\SQLEXPRESS"

Set-Value -Key 'configDBServer'      -ParamValue $ConfigDbServer      -Description 'SQL Server name where the Config DB sits.'                                                              -Default $defaultSqlServer
Set-Value -Key 'configDb'            -ParamValue $ConfigDb            -Description 'Config database name (e.g. Flintfox.Azara.Data.Config.SQL or RMx_Config).'                              -Default 'Flintfox.Azara.Data.Config.SQL'
Set-Value -Key 'tenantDbServer'      -ParamValue $TenantDbServer      -Description 'SQL Server name where the Tenant DB sits.'                                                              -Default $defaultSqlServer
Set-Value -Key 'tenantDb'            -ParamValue $TenantDb            -Description 'Tenant database name (e.g. RMx_Training, FlintfoxTenantDB).'
Set-Value -Key 'username'            -ParamValue $SqlUsername         -Description 'SQL Server login name (e.g. sa, ffa-sql-login).'                                                        -Default 'sa'
Set-Value -Key 'password'            -ParamValue $SqlPassword         -Description 'SQL Server login password.'                                                                              -Secret
Set-Value -Key 'versionFolder'       -ParamValue $FfaVersion          -Description 'FFA version used for the install (matches Binaries subfolder).'                                         -Default $FfaVersion
Set-Value -Key 'targetEnvironment'   -ParamValue $VmName              -Description 'VM hostname where FFA is installed.'                                                                    -Default $VmName
Set-Value -Key 'tenantUniqueName'    -ParamValue $TenantUniqueName    -Description 'Unique tenant key inserted into the Config DB az_Tenant table.'
Set-Value -Key 'version'             -ParamValue $DatabaseVersion     -Description 'FFA database version (often the same as versionFolder).'                                                -Default $FfaVersion
Set-Value -Key 'platformWebRoot'     -ParamValue $PlatformWebRoot     -Description 'Folder where the Platform Web component installs.'                                                       -Default 'C:\Program Files\Flintfox International\RMx Web Application'
Set-Value -Key 'odataWebRoot'        -ParamValue $OdataWebRoot        -Description 'Folder where the oData Web component installs.'                                                          -Default 'C:\Program Files\Flintfox International\RMx oData Application'
Set-Value -Key 'platformServiceroot' -ParamValue $PlatformServiceRoot -Description 'Folder where the Service component installs (note lowercase r in serviceroot - matches FFA template).'  -Default 'C:\Program Files\Flintfox International\RMx Service Application'

$config | ConvertTo-Json -Depth 10 | Set-Content -Path $targetJsonPath -Encoding UTF8
Write-Ok "Saved: $targetJsonPath"

Write-Host ''
Write-Host 'Installation JSON configuration complete.'
Write-Host 'Next: run 09-Setup-Binaries.ps1 to download the pipeline drop and DacPacs.' -ForegroundColor Yellow
