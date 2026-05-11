# =============================================================================
#  04 - Install developer tools
#  This script installs SQL Server Management Studio 22 and Visual Studio Code.
#  Set $env:SKIP_SSMS = 1 to skip SSMS, or $env:SKIP_VSCODE = 1 to skip VS Code.
# =============================================================================
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

Write-Ok 'Installing developer tools: SSMS and Visual Studio Code.'

function Test-SsmsInstalled {
    $candidates = @(
        'C:\Program Files\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\Ssms.exe',
        'C:\Program Files\Microsoft SQL Server Management Studio 22\Common7\IDE\Ssms.exe',
        'C:\Program Files (x86)\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\Ssms.exe',
        'C:\Program Files (x86)\Microsoft SQL Server Management Studio 22\Common7\IDE\Ssms.exe',
        'C:\Program Files\Microsoft SQL Server Management Studio\Common7\IDE\Ssms.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $true } }
    $entries = Get-ItemProperty `
        HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
        HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
        -ErrorAction SilentlyContinue
    return $null -ne ($entries | Where-Object {
        $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like '*SQL Server Management Studio*'
    })
}

function Test-VsCodeInstalled {
    if (Get-Command code -ErrorAction SilentlyContinue) { return $true }
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "$env:ProgramFiles\Microsoft VS Code\Code.exe",
        "$env:ProgramFiles(x86)\Microsoft VS Code\Code.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $true } }
    return $false
}

if ($Cfg.SkipSsms) {
    Write-Ok 'Skipping SSMS install ($env:SKIP_SSMS=1)'
} elseif (Test-SsmsInstalled) {
    Write-Ok 'SSMS 22 already installed - skipping'
} else {
    $Cfg.SsmsInstallerUrl = if ([string]::IsNullOrEmpty($Cfg.SsmsInstallerUrl)) {
        'https://aka.ms/ssms/22/release/vs_SSMS.exe'
    } else {
        $Cfg.SsmsInstallerUrl
    }

    Write-Log "SSMS install not found on disk; retrieving installer from $($Cfg.SsmsInstallerUrl)"
    $ssmsExe = Join-Path $Cfg.PrereqsTempDir 'vs_SSMS.exe'
    Invoke-WebDownload -Url $Cfg.SsmsInstallerUrl -OutFile $ssmsExe
    Assert-MicrosoftSigned -Path $ssmsExe

    Write-Log 'Installing SSMS 22 (silent, no restart)'
    $proc = Start-Process -FilePath $ssmsExe `
        -ArgumentList '--quiet','--norestart','--wait' `
        -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) { Write-Err "SSMS installer exited $($proc.ExitCode)" }
    Write-Ok 'SSMS 22 installed'

    if (-not (Test-SsmsInstalled)) {
        Write-Warn 'SSMS expected install path not found post-install. Check %ProgramFiles%\Microsoft SQL Server Management Studio 22\.'
    }
}

if ($Cfg.SkipVsCode) {
    Write-Ok 'Skipping Visual Studio Code install ($env:SKIP_VSCODE=1)'
} elseif (Test-VsCodeInstalled) {
    Write-Ok 'Visual Studio Code already installed - skipping'
} else {
    $Cfg.VsCodeInstallerUrl = if ([string]::IsNullOrEmpty($Cfg.VsCodeInstallerUrl)) {
        'https://update.code.visualstudio.com/latest/win32-x64-user/stable'
    } else {
        $Cfg.VsCodeInstallerUrl
    }

    Write-Log "VS Code install not found on disk; retrieving installer from $($Cfg.VsCodeInstallerUrl)"
    $vsCodeExe = Join-Path $Cfg.PrereqsTempDir 'VSCodeSetup.exe'
    Invoke-WebDownload -Url $Cfg.VsCodeInstallerUrl -OutFile $vsCodeExe
    Assert-MicrosoftSigned -Path $vsCodeExe

    Write-Log 'Installing Visual Studio Code (silent, no auto-launch)'
    $proc = Start-Process -FilePath $vsCodeExe `
        -ArgumentList '/silent','/mergetasks=!runcode' `
        -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) { Write-Err "VS Code installer exited $($proc.ExitCode)" }
    Write-Ok 'Visual Studio Code installed'

    if (-not (Test-VsCodeInstalled)) {
        Write-Warn 'VS Code expected install path not found post-install. Check the VS Code install directory.'
    }
}
