# =============================================================================
#  10 - Run the FFA pre-install scripts in order
#  Invokes the Flintfox-supplied pre-install + initial-setup scripts that come
#  with the installer.zip (extracted by 07).
# =============================================================================
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin

$scriptsFolder = Join-Path $Cfg.InstallRoot 'ManualInstallationScripts'
if (-not (Test-Path $scriptsFolder)) {
    Write-Err "$scriptsFolder not found - run 07-Download-Installer.ps1 first"
}

Set-ExecutionPolicy Bypass -Scope LocalMachine -Force | Out-Null
Write-Ok 'Execution policy: Bypass (LocalMachine)'

$preInstallSequence = @(
    'PreInstall-Configure-Firewall.ps1',
    'PreInstall-Configure-Firewall-For-Service.ps1',
    'PreInstall-Configure-Firewall-For-WebSites.ps1',
    'PreInstall-Generate-Localhost-Certificate.ps1',
    '00-StopApplications.ps1',
    '01-DeployConfigDb.ps1'
)

Push-Location $scriptsFolder
try {
    foreach ($s in $preInstallSequence) {
        $path = Join-Path $scriptsFolder $s
        if (-not (Test-Path $path)) {
            Write-Warn "Skipping (not found): $s"
            continue
        }
        Write-Log "Running $s"
        # Reset $LASTEXITCODE before each call - dot-sourcing or invoking a .ps1
        # does NOT set it (only external .exe commands do). Strict-mode reads of
        # an uninitialized $LASTEXITCODE throw "VariableIsUndefined".
        $global:LASTEXITCODE = 0
        try {
            & $path
        } catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg -like "*Cannot find any service with service name 'RMxPlatformService'*") {
                Write-Warn "$s : $errorMsg (service not found on this system - continuing)"
            } else {
                Write-Err "$s threw: $errorMsg"
            }
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Err "$s exited with code $LASTEXITCODE"
        }
        Write-Ok "Completed $s"
    }
} finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Next: run 11-Install-FFA.ps1 to invoke the main InstallFFA.ps1' -ForegroundColor Yellow
