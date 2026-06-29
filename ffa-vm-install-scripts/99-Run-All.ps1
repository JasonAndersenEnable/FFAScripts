# =============================================================================
#  99 - Run all in-VM setup steps in order.
#  Auto-runs 01-05 (the no-prompt OS prep). Steps 06-11 are interactive or
#  parameter-driven and must be run individually.
# =============================================================================
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin

& "$PSScriptRoot/01-Configure-IIS.ps1"
& "$PSScriptRoot/02-Install-DotNet.ps1"
& "$PSScriptRoot/03-Install-UrlRewrite.ps1"
& "$PSScriptRoot/04-Install-Tools.ps1"
& "$PSScriptRoot/05-Verify-Prerequisites.ps1"

Write-Host ''
Write-Ok 'OS prep complete (steps 01-05).'
Write-Host 'Run the remaining steps individually:' -ForegroundColor Yellow
Write-Host '  06 - Optional: SSL cert     ./06-Import-SSL-Certificate.ps1 -PfxPath ... -PfxPassword ...'
Write-Host '  07 - FFA installer scripts  ./07-Download-Installer.ps1'
Write-Host '  08 - Tenant JSON config     ./08-Configure-Tenant-Json.ps1'
Write-Host '  09 - Binaries + DacPacs     ./09-Setup-Binaries.ps1'
Write-Host '  10 - Pre-install scripts    ./10-Run-PreInstall.ps1'
Write-Host '  11 - InstallFFA.ps1         ./11-Install-FFA.ps1'
