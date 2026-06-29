# =============================================================================
#  02 - Install .NET runtime, ASP.NET Core runtime, Hosting Bundle (pinned)
#  ORDER: Run 01 first - IIS must be present before the Hosting Bundle's IIS
#         registration step (ANCM v2) can succeed.
#
#  Components:
#  - dotnet-runtime-X.Y.Z-win-x64.exe       (.NET base runtime)
#  - aspnetcore-runtime-X.Y.Z-win-x64.exe   (ASP.NET Core runtime)
#  - dotnet-hosting-X.Y.Z-win.exe           (Hosting Bundle - registers ANCM v2)
#
#  Each install is signature-verified and skipped if the target version is
#  already present. ANCM v2 force-copy fallback runs after the bundle install
#  in case the MSI's IIS-side custom action silently failed.
# =============================================================================
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin
Import-Module WebAdministration -ErrorAction Stop

$DotnetTargetVersion = $Cfg.DotnetTargetVersion
$DotnetInstallDir    = Join-Path $env:ProgramFiles 'dotnet'
$AncmDllPath         = Join-Path $env:WINDIR 'System32\inetsrv\aspnetcorev2.dll'
$script:DotnetReleaseMetadata = $null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

function Test-DotnetRuntimeInstalled {
    param(
        [Parameter(Mandatory)][string]$ComponentName,
        [string]$Version
    )
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { return $false }
    $runtimes = & dotnet --list-runtimes 2>$null
    if ($Version) {
        $pattern = "^$([regex]::Escape($ComponentName))\s+$([regex]::Escape($Version))(\s|$)"
    } else {
        $pattern = "^$([regex]::Escape($ComponentName))\s+8\."
    }
    return ($runtimes | Where-Object { $_ -match $pattern }) -ne $null
}

function Get-DotNet8File {
    param(
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string[]]$NamePatterns,
        [string]$TargetVersion = $DotnetTargetVersion
    )
    Write-Log "Resolving $Section file (version $TargetVersion) matching: $($NamePatterns -join ', ')"
    if (-not $script:DotnetReleaseMetadata) {
        $script:DotnetReleaseMetadata = Invoke-RestMethod -Uri $Cfg.DotnetReleasesJson -UseBasicParsing
    }
    $json = $script:DotnetReleaseMetadata
    $release = $json.releases | Where-Object { $_.'release-version' -eq $TargetVersion } | Select-Object -First 1
    if (-not $release) {
        $available = ($json.releases | Where-Object { $_.'release-version' -notmatch '-' } |
                      Select-Object -First 10 | ForEach-Object { $_.'release-version' }) -join ', '
        Write-Err "Version '$TargetVersion' not found. Recent stable: $available ..."
    }
    $sectionData = $release.$Section
    if (-not $sectionData) {
        $sections = ($release.PSObject.Properties.Name) -join ', '
        Write-Err "Section '$Section' missing in release $TargetVersion. Available sections: $sections"
    }
    foreach ($pat in $NamePatterns) {
        $file = $sectionData.files | Where-Object { $_.name -like $pat } | Select-Object -First 1
        if ($file) { Write-Log "Matched '$pat' -> $($file.name)"; return $file }
    }
    $available = $sectionData.files | ForEach-Object { "    $($_.name)" } | Out-String
    Write-Err "No file matched [$($NamePatterns -join ', ')] in '$Section' of release $TargetVersion.`nAvailable:`n$available"
}

# --- 1. .NET base runtime ---------------------------------------------------
if (Test-DotnetRuntimeInstalled -ComponentName 'Microsoft.NETCore.App' -Version $DotnetTargetVersion) {
    Write-Ok ".NET runtime $DotnetTargetVersion already installed - skipping"
} else {
    $rt = Get-DotNet8File -Section 'runtime' -NamePatterns @(
        "dotnet-runtime-$DotnetTargetVersion-win-x64.exe",
        "dotnet-runtime-$DotnetTargetVersion-x64.exe",
        'dotnet-runtime-*-win-x64.exe',
        'dotnet-runtime-win-x64.exe'
    )
    $exe = Join-Path $Cfg.PrereqsTempDir $rt.name
    Invoke-WebDownload -Url $rt.url -OutFile $exe
    Assert-MicrosoftSigned -Path $exe
    Write-Log "Installing $($rt.name) (silent)"
    $proc = Start-Process -FilePath $exe -ArgumentList '/quiet','/norestart' -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) { Write-Err "Runtime installer exited $($proc.ExitCode)" }
    if ($env:Path -notlike "*$DotnetInstallDir*") { $env:Path += ";$DotnetInstallDir" }
    Write-Ok ".NET runtime $DotnetTargetVersion installed"
}

# --- 2. ASP.NET Core runtime ------------------------------------------------
if (Test-DotnetRuntimeInstalled -ComponentName 'Microsoft.AspNetCore.App' -Version $DotnetTargetVersion) {
    Write-Ok "ASP.NET Core runtime $DotnetTargetVersion already installed - skipping"
} else {
    $aspnet = Get-DotNet8File -Section 'aspnetcore-runtime' -NamePatterns @(
        "aspnetcore-runtime-$DotnetTargetVersion-win-x64.exe",
        'aspnetcore-runtime-*-win-x64.exe',
        'aspnetcore-runtime-win-x64.exe'
    )
    $exe = Join-Path $Cfg.PrereqsTempDir $aspnet.name
    Invoke-WebDownload -Url $aspnet.url -OutFile $exe
    Assert-MicrosoftSigned -Path $exe
    Write-Log "Installing $($aspnet.name) (silent)"
    $proc = Start-Process -FilePath $exe -ArgumentList '/quiet','/norestart' -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) { Write-Err "ASP.NET Core installer exited $($proc.ExitCode)" }
    Write-Ok "ASP.NET Core runtime $DotnetTargetVersion installed"
}

# --- 3. Hosting Bundle (registers ANCM v2 into IIS) -------------------------
if ((Test-DotnetRuntimeInstalled -ComponentName 'Microsoft.AspNetCore.App' -Version $DotnetTargetVersion) -and
    (Test-Path $AncmDllPath)) {
    Write-Ok "Hosting Bundle $DotnetTargetVersion already installed (ANCM present) - skipping"
} else {
    $bundle = Get-DotNet8File -Section 'aspnetcore-runtime' -NamePatterns @(
        "dotnet-hosting-$DotnetTargetVersion-win.exe",
        'dotnet-hosting-*-win.exe',
        'dotnet-hosting-*-win-x64.exe',
        'dotnet-hosting-win.exe'
    )
    $exe = Join-Path $Cfg.PrereqsTempDir $bundle.name
    Invoke-WebDownload -Url $bundle.url -OutFile $exe
    Assert-MicrosoftSigned -Path $exe
    Write-Log "Installing $($bundle.name) (silent)"
    $proc = Start-Process -FilePath $exe -ArgumentList '/quiet','/norestart' -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) { Write-Err "Hosting Bundle installer exited $($proc.ExitCode)" }
    Write-Ok "Hosting Bundle $DotnetTargetVersion installed"
}

# ANCM v2 force-copy fallback - the bundle's MSI custom action that copies
# aspnetcorev2.dll to inetsrv\ has been observed to silently fail.
if (-not (Test-Path $AncmDllPath)) {
    $ancmSources = @(
        'C:\Program Files\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll',
        'C:\Program Files (x86)\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll'
    )
    $src = $ancmSources | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($src) {
        Write-Warn "ANCM v2 missing from inetsrv - force-copying from $src"
        Copy-Item -Path $src -Destination $AncmDllPath -Force
        Write-Ok "ANCM v2 copied to $AncmDllPath"
    } else {
        Write-Warn 'ANCM v2 missing from inetsrv AND from both bundle source paths.'
        Write-Warn 'Bundle install did not lay the module on disk - manual reinstall needed.'
    }
}

# --- iisreset so newly registered modules are picked up ---------------------
Write-Log 'Restarting IIS (iisreset /noforce)'
iisreset /noforce | Out-Null
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Service W3SVC).Status -ne 'Running' -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
}
if ((Get-Service W3SVC).Status -ne 'Running') {
    Write-Err 'W3SVC did not return to Running within 30s after iisreset'
}
Write-Ok 'IIS restarted'

# --- Verification (only this script's slice) --------------------------------
$checks = @(
    @{ Name = ".NET runtime $DotnetTargetVersion"; Test = { Test-DotnetRuntimeInstalled -ComponentName 'Microsoft.NETCore.App'    -Version $DotnetTargetVersion } },
    @{ Name = "ASP.NET Core $DotnetTargetVersion"; Test = { Test-DotnetRuntimeInstalled -ComponentName 'Microsoft.AspNetCore.App' -Version $DotnetTargetVersion } },
    @{ Name = 'IIS W3SVC running';                 Test = { (Get-Service W3SVC).Status -eq 'Running' } },
    @{ Name = 'ANCM v2 present';                   Test = { Test-Path $AncmDllPath } }
)
foreach ($c in $checks) {
    if (& $c.Test) { Write-Ok $c.Name } else { Write-Warn "$($c.Name): FAIL" }
}

Write-Host ''
Write-Ok 'DotNET installation complete.'
Write-Host 'Next: run 03-Install-UrlRewrite.ps1' -ForegroundColor Yellow