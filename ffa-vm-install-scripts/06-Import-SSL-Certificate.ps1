# =============================================================================
#  06 - Import a CA-signed PFX into the Local Machine certificate store
#  PS1 source: Invoke-Script05-ImportSSLCertificate
#  OPTIONAL for dev. Required before binding the FFA portal to HTTPS in prod.
#
#  Usage:
#    ./05-Import-SSL-Certificate.ps1 -PfxPath C:\path\to\cert.pfx -PfxPassword '...'
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PfxPath,
    [Parameter(Mandatory)][string] $PfxPassword,
    [string] $StoreName     = 'My',
    [string] $StoreLocation = 'LocalMachine'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin

if (-not (Test-Path $PfxPath)) { Write-Err "PFX file not found: $PfxPath" }
$securePwd = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
$cert = Import-PfxCertificate `
    -FilePath $PfxPath `
    -CertStoreLocation "Cert:\$StoreLocation\$StoreName" `
    -Password $securePwd

Write-Ok 'Certificate imported'
Write-Host "  Subject    : $($cert.Subject)"
Write-Host "  Thumbprint : $($cert.Thumbprint)"
Write-Host "  Expiry     : $($cert.NotAfter)"

# Save details for the consultant doing the IIS binding (under the consolidated FFA root)
$detailsPath = Join-Path $Cfg.InstallRoot 'cert-details.csv'
[PSCustomObject]@{
    Thumbprint = $cert.Thumbprint
    Subject    = $cert.Subject
    Expiry     = $cert.NotAfter
    Store      = "Cert:\$StoreLocation\$StoreName"
} | Export-Csv -Path $detailsPath -NoTypeInformation
Write-Host "  Details saved: $detailsPath"


Write-Host ''
Write-Ok 'Import Certificate complete.'
Write-Host 'Next: run 07-Download-Installer.ps1' -ForegroundColor Yellow