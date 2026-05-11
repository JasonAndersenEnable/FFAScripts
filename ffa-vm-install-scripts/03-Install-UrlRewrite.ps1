# =============================================================================
#  03 - Install IIS URL Rewrite Module 2.1
#  ORDER: Run 02 (IIS) first. Independent of 03a.
# =============================================================================
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin
Import-Module WebAdministration -ErrorAction Stop

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

function Test-UrlRewriteInstalled {
    try {
        $mod = Get-WebConfiguration 'system.webServer/globalModules/*' -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -eq 'RewriteModule' }
        return $null -ne $mod
    } catch { return $false }
}

if (Test-UrlRewriteInstalled) {
    Write-Ok 'URL Rewrite Module already installed - skipping'
    return
}

Write-Log 'Downloading IIS URL Rewrite Module 2.1'
$rewriteMsi = Join-Path $Cfg.PrereqsTempDir 'rewrite_amd64_en-US.msi'
Invoke-WebDownload -Url $Cfg.UrlRewriteMsiUrl -OutFile $rewriteMsi
Assert-MicrosoftSigned -Path $rewriteMsi

Write-Log 'Installing URL Rewrite Module 2.1 (silent)'
$proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', "`"$rewriteMsi`"", '/quiet', '/norestart' -Wait -PassThru
if ($proc.ExitCode -notin @(0, 3010)) { Write-Err "URL Rewrite installer exited $($proc.ExitCode)" }
Write-Ok 'URL Rewrite Module 2.1 installed'

Write-Log 'Restarting IIS to pick up the new module'
iisreset /noforce | Out-Null
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Service W3SVC).Status -ne 'Running' -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
if ((Get-Service W3SVC).Status -ne 'Running') { Write-Err 'W3SVC did not return to Running within 30s' }
Write-Ok 'IIS restarted'

if (Test-UrlRewriteInstalled) { Write-Ok 'URL Rewrite verified' } else { Write-Warn 'URL Rewrite: FAIL' }
