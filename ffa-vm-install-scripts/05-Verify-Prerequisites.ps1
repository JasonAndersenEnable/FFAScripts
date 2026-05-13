# =============================================================================
#  05 - Verify all prerequisites installed by 01-04 are present and healthy
#  Read-only check. Safe to run any time. Returns a structured result table.
# =============================================================================
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"

Import-Module WebAdministration -ErrorAction SilentlyContinue

$DotnetTargetVersion = $Cfg.DotnetTargetVersion
$AncmDllPath = Join-Path $env:WINDIR 'System32\inetsrv\aspnetcorev2.dll'

function Test-DotnetRuntimeInstalled {
    param([string]$ComponentName, [string]$Version)
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { return $false }
    $runtimes = & dotnet --list-runtimes 2>$null
    if ($Version) {
        $pattern = "^$([regex]::Escape($ComponentName))\s+$([regex]::Escape($Version))(\s|$)"
    }
    else {
        $pattern = "^$([regex]::Escape($ComponentName))\s+8\."
    }
    return $runtimes -match $pattern 
}

function Test-UrlRewriteInstalled {
    try {
        $mod = Get-WebConfiguration 'system.webServer/globalModules/*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'RewriteModule' }
        return $null -ne $mod
    }
    catch { return $false }
}

function Test-SsmsInstalled {
    # Known install paths (SSMS 22 added a "Release" subfolder under the version dir)
    $candidates = @(
        'C:\Program Files\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\Ssms.exe',
        'C:\Program Files\Microsoft SQL Server Management Studio 22\Common7\IDE\Ssms.exe',
        'C:\Program Files (x86)\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\Ssms.exe',
        'C:\Program Files (x86)\Microsoft SQL Server Management Studio 22\Common7\IDE\Ssms.exe',
        'C:\Program Files\Microsoft SQL Server Management Studio\Common7\IDE\Ssms.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $true } }
    # Registry fallback - works for any version without path maintenance
    $entries = Get-ItemProperty `
        HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
        HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
        -ErrorAction SilentlyContinue
    return $null -ne ($entries | Where-Object { $_.DisplayName -like '*SQL Server Management Studio*' })
}

$checks = @(
    @{ Name = 'IIS feature installed'; Test = { (Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue).InstallState -eq 'Installed' } },
    @{ Name = 'IIS W3SVC running'; Test = { (Get-Service W3SVC -ErrorAction SilentlyContinue).Status -eq 'Running' } },
    @{ Name = "Firewall rule: FFA-HTTP-HTTPS"; Test = { $null -ne (Get-NetFirewallRule -DisplayName 'FFA-HTTP-HTTPS' -ErrorAction SilentlyContinue) } },
    @{ Name = "Firewall rule: FFA-App-Ports"; Test = { $null -ne (Get-NetFirewallRule -DisplayName 'FFA-App-Ports'  -ErrorAction SilentlyContinue) } },
    @{ Name = "Firewall rule: FFA-SQL"; Test = { $null -ne (Get-NetFirewallRule -DisplayName 'FFA-SQL'        -ErrorAction SilentlyContinue) } },
    @{ Name = ".NET runtime $DotnetTargetVersion"; Test = { Test-DotnetRuntimeInstalled -ComponentName 'Microsoft.NETCore.App'    -Version $DotnetTargetVersion } },
    @{ Name = "ASP.NET Core $DotnetTargetVersion"; Test = { Test-DotnetRuntimeInstalled -ComponentName 'Microsoft.AspNetCore.App' -Version $DotnetTargetVersion } },
    @{ Name = 'ANCM v2 present'; Test = { Test-Path $AncmDllPath } },
    @{ Name = 'URL Rewrite'; Test = { Test-UrlRewriteInstalled } },
    @{ Name = 'SSMS 22 installed'; Test = { Test-SsmsInstalled } }
)

$allOk = $true
$results = foreach ($c in $checks) {
    $ok = & $c.Test
    if ($ok) { Write-Ok $c.Name } else { Write-Warn "$($c.Name): FAIL"; $allOk = $false }
    [pscustomobject]@{ Name = $c.Name; Status = if ($ok) { 'OK' } else { 'FAIL' } }
}

$results

if ($allOk) {
    Write-Ok 'All prerequisites verified.'

    Write-Host ''
    Write-Host 'Verification complete.'
    Write-Host 'Next: run 06-Import-SSL-Certificate.ps1 or skip to run 07-Download-Installer.ps1.' -ForegroundColor Yellow

}
else {
    Write-Warn 'One or more checks failed - re-run the matching install script (01-04) before proceeding.'
}
