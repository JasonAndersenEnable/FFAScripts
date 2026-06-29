# =============================================================================
#  07 - Download FFA installer scripts and rename Installation JSON
#  Replaces sections 1-2 of the old 07-Download-Prepare-FFA.ps1.
# =============================================================================
[CmdletBinding()]
param(
    [string] $InstallerZipPath,
    [string] $VmName = $env:COMPUTERNAME
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin

function Read-ZipPath {
    param([Parameter(Mandatory)][string]$Prompt)
    $defaultDownloads = Join-Path $env:USERPROFILE 'Downloads'
    $p = Read-Host "$Prompt (looking under $defaultDownloads first)"
    $p = $p.Trim('"', "'", ' ')
    if ([string]::IsNullOrEmpty($p)) {
        $candidate = Get-ChildItem -Path $defaultDownloads -Filter '*.zip' -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($candidate) {
            Write-Log "Using most recent .zip in Downloads: $($candidate.FullName)"
            return $candidate.FullName
        }
    }
    if (-not (Test-Path $p)) { Write-Err "Path not found: $p" }
    return $p
}

# --- Section 1: download installer scripts ----------------------------------
$scriptsFolder = Join-Path $Cfg.InstallRoot 'ManualInstallationScripts'
# Skip the download if BOTH the scripts folder exists AND an Installation JSON
# is already present in either expected location (install root preferred).
$jsonAlreadyPresent = @($Cfg.InstallRoot, $scriptsFolder) |
                       ForEach-Object { Get-ChildItem -Path $_ -Filter 'Installation.*.json' -ErrorAction SilentlyContinue } |
                       Select-Object -First 1
if ((Test-Path $scriptsFolder) -and $jsonAlreadyPresent) {
    Write-Ok "Installer scripts already extracted at $scriptsFolder - skipping download"
} else {
    Write-Host ''
    Write-Host 'Open a browser and:' -ForegroundColor Yellow
    Write-Host '  1) Go to: https://flintfox.visualstudio.com/_git/FFA'
    Write-Host '  2) Authenticate (Flintfox / VSTS account)'
    Write-Host '  3) Confirm the master branch is selected'
    Write-Host '  4) Navigate to the "installer" folder'
    Write-Host '  5) Click the three dots in the top-right of that folder'
    Write-Host '  6) Choose "Download as ZIP" - saves as installer.zip'
    Write-Host ''
    if ([string]::IsNullOrEmpty($InstallerZipPath)) {
        $InstallerZipPath = Read-ZipPath 'Path to downloaded installer.zip'
    } elseif (-not (Test-Path $InstallerZipPath)) {
        Write-Err "InstallerZipPath not found: $InstallerZipPath"
    }
    Write-Log "Extracting $InstallerZipPath -> $($Cfg.InstallRoot)"
    Expand-Archive -Path $InstallerZipPath -DestinationPath $Cfg.InstallRoot -Force

    # Flatten if the ZIP wraps content in an outer folder
    if (-not (Test-Path $scriptsFolder)) {
        $nested = Get-ChildItem -Path $Cfg.InstallRoot -Directory |
                  Where-Object { Test-Path (Join-Path $_.FullName 'ManualInstallationScripts') } |
                  Select-Object -First 1
        if ($nested) {
            Write-Log "Flattening nested structure from $($nested.Name)"
            # Move-Item -Force does NOT merge directories - if the destination subfolder
            # already exists (Initialize-FfaDirectories created Binaries\ and Prereqs\),
            # the move fails. Walk each entry and copy-merge directories, move files.
            Get-ChildItem -Path $nested.FullName -Force | ForEach-Object {
                $dest = Join-Path $Cfg.InstallRoot $_.Name
                if ($_.PSIsContainer -and (Test-Path $dest)) {
                    # Destination dir already exists - merge contents into it
                    Copy-Item -Path (Join-Path $_.FullName '*') -Destination $dest -Recurse -Force
                    Remove-Item $_.FullName -Recurse -Force
                } else {
                    # File, or directory whose target doesn't exist yet
                    Move-Item -Path $_.FullName -Destination $dest -Force
                }
            }
            Remove-Item $nested.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not (Test-Path $scriptsFolder)) {
        Write-Err "ManualInstallationScripts folder not found after extracting installer.zip - check the contents"
    }
    Write-Ok "Installer scripts extracted: $scriptsFolder"
}

# --- Section 2: rename Installation JSON to match this VM's hostname --------
# The FFA repo's installer ZIP puts Installation.MACHINE-NAME.json at the
# install root level (a sibling of ManualInstallationScripts\). Older bundles
# put it inside ManualInstallationScripts. Look in both places.
$targetJsonName = "Installation.$VmName.json"
$searchFolders  = @($Cfg.InstallRoot, $scriptsFolder)

# Already renamed in either location?
$existing = $searchFolders |
            ForEach-Object { Join-Path $_ $targetJsonName } |
            Where-Object   { Test-Path $_ } |
            Select-Object  -First 1
if ($existing) {
    Write-Ok "Already renamed: $existing"
    $targetJsonPath = $existing
} else {
    # Find template in either location, prefer InstallRoot
    $template = $null
    foreach ($folder in $searchFolders) {
        $template = Get-ChildItem -Path $folder -Filter 'Installation.*.json' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notlike "*$VmName*" } |
                    Select-Object -First 1
        if ($template) { break }
    }
    if (-not $template) {
        Write-Err "No Installation.*.json template found in $($searchFolders -join ' or ')"
    }
    Write-Log "Renaming $($template.FullName) -> $targetJsonName"
    Rename-Item -Path $template.FullName -NewName $targetJsonName
    $targetJsonPath = Join-Path $template.DirectoryName $targetJsonName
    Write-Ok "Renamed: $targetJsonPath"
}

Set-ExecutionPolicy Bypass -Scope LocalMachine -Force
Write-Ok 'Execution policy set to Bypass (LocalMachine)'

Write-Host ''
Write-Host 'Download Installer complete.'
Write-Host 'Next: run 08-Configure-Tenant-Json.ps1 to populate the Installation JSON values.' -ForegroundColor Yellow
