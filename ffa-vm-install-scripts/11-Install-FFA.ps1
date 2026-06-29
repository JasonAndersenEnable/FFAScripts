# =============================================================================
#  11 - Invoke the main FFA installer (InstallFFA.ps1)
#  Last step. Assumes 01-10 have succeeded.
# =============================================================================
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin

$scriptsFolder = Join-Path $Cfg.InstallRoot 'ManualInstallationScripts'
$installer     = Join-Path $scriptsFolder 'InstallFFA.ps1'
if (-not (Test-Path $installer)) {
    Write-Err "InstallFFA.ps1 not found at $installer - run 07 first"
}

# Confirm the Installation JSON is in place (in either expected location)
$candidateJsonPaths = @(
    (Join-Path $Cfg.InstallRoot "Installation.$env:COMPUTERNAME.json"),
    (Join-Path $scriptsFolder   "Installation.$env:COMPUTERNAME.json")
)
$jsonPath = $candidateJsonPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $jsonPath) {
    Write-Err "Installation.$env:COMPUTERNAME.json not found in $($candidateJsonPaths -join ' or ') - run 07 then 08 first"
}

Write-Log "Invoking $installer"
Push-Location $scriptsFolder
try {
    # Reset $LASTEXITCODE - dot-sourcing/invoking a .ps1 doesn't set it under
    # Set-StrictMode -Version Latest, so an uninitialized read throws.
    $global:LASTEXITCODE = 0
    try {
        & $installer
    } catch {
        Write-Err "InstallFFA.ps1 threw: $($_.Exception.Message)"
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Err "InstallFFA.ps1 exited with code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Ok 'FFA installation invoked. Watch the InstallFFA.ps1 output for any failures.'
