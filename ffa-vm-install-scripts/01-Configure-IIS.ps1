# =============================================================================
#  01 - Install IIS + Windows Firewall rules
#  Merged from:
#    - 02-Configure-IIS-Firewall (IIS install + base firewall rules)
#    - the former FFA port refresh logic from the old 04 script
#  PS1 source: Invoke-Script02-ConfigureIISFirewall
#  Run: Local Administrator INSIDE the VM
# =============================================================================
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin

Write-Log 'Installing IIS and required Windows features'
$features = @(
    'Web-Server','Web-WebServer','Web-Common-Http','Web-Static-Content',
    'Web-Default-Doc','Web-Http-Errors','Web-App-Dev','Web-Asp-Net45',
    'Web-Net-Ext45','Web-ISAPI-Ext','Web-ISAPI-Filter','Web-Health',
    'Web-Http-Logging','Web-Security','Web-Request-Monitor',
    'Web-Mgmt-Tools','Web-Mgmt-Console','NET-Framework-45-Features',
    'NET-Framework-45-Core','NET-WCF-HTTP-Activation45'
)
$result = Install-WindowsFeature -Name $features -IncludeManagementTools
if (-not $result.Success) { Write-Err 'IIS installation failed' }
Write-Ok 'IIS installed'

Write-Log 'Configuring Windows Firewall rules (HTTP/HTTPS, FFA app ports, SQL)'
$rules = @(
    @{ Name = 'FFA-HTTP-HTTPS'; Ports = @(80, 443);                 Scope = 'Any' },
    @{ Name = 'FFA-App-Ports' ; Ports = $Cfg.FfaAppPorts;            Scope = 'Any' },
    @{ Name = 'FFA-SQL'       ; Ports = @(1433);                     Scope = 'LocalSubnet' }
)
foreach ($r in $rules) {
    if (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -DisplayName $r.Name
    }
    New-NetFirewallRule -DisplayName $r.Name -Direction Inbound `
        -Protocol TCP -LocalPort $r.Ports -RemoteAddress $r.Scope `
        -Action Allow -Enabled True | Out-Null
    Write-Ok "Firewall rule: $($r.Name)"
}

Write-Host ''
Write-Host 'Port verification (binding shows after FFA install):' -ForegroundColor Yellow
$portsToCheck = @(80, 443) + $Cfg.FfaAppPorts + @(1433)
foreach ($p in $portsToCheck) {
    $r = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
    $status = if ($r.TcpTestSucceeded) { 'OPEN' } else { 'not yet bound' }
    Write-Host ("  {0,-5} : {1}" -f $p, $status)
}

Write-Host ''
Write-Ok 'IIS and firewall configuration complete.'
