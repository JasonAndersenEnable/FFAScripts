# =============================================================================
#  09 - Set up Binaries\<FfaVersion> from pipeline drop + DacPacs fallback
#  Replaces sections 4-7 of the old 07-Download-Prepare-FFA.ps1.
#
#  What it does:
#    1. Extracts the two ManualInstallationTools ZIPs (resourceinstaller, sqlpackage)
#    2. Renames Binaries\Version Template -> Binaries\<FfaVersion>; verifies the
#       four subfolders exist (Apps, DacPacs, Plugins, Solutions)
#    3. Overlays the all-in-one pipeline 'drop' artifact into Binaries\<FfaVersion>\
#    4. Verifies the four required DacPacs; if Config DacPac missing, prompts for
#       the build-config-db-dacpac drop and overlays just that file
# =============================================================================
[CmdletBinding()]
param(
    [string] $BinariesZipPath,
    [string] $ConfigDacpacZipPath,
    [string] $FfaVersion
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
Assert-Admin

if ([string]::IsNullOrEmpty($FfaVersion)) { $FfaVersion = $Cfg.FfaVersion }

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

# --- 1. Extract ManualInstallationTools ZIPs --------------------------------
$toolsFolder = Join-Path $Cfg.InstallRoot 'ManualInstallationTools'
if (-not (Test-Path $toolsFolder)) {
    Write-Warn "$toolsFolder not found - run 07-Download-Installer.ps1 first"
} else {
    Get-ChildItem -Path $toolsFolder -Filter '*.zip' | ForEach-Object {
        $extractDir = Join-Path $toolsFolder ($_.BaseName)
        if ((Test-Path $extractDir) -and (Get-ChildItem $extractDir -ErrorAction SilentlyContinue)) {
            Write-Ok "Already extracted: $($_.Name)"
        } else {
            Write-Log "Extracting $($_.Name) -> $extractDir"
            Expand-Archive -Path $_.FullName -DestinationPath $extractDir -Force
            Write-Ok "Extracted: $($_.Name)"
        }
    }
}

# --- 2. Set up Binaries\<FfaVersion> ---------------------------------------
$binariesVersionPath = Join-Path $Cfg.BinariesRoot $FfaVersion
$versionTemplatePath = Join-Path $Cfg.BinariesRoot 'Version Template'

if (Test-Path $binariesVersionPath) {
    Write-Ok "Already exists: $binariesVersionPath"
} elseif (Test-Path $versionTemplatePath) {
    Write-Log "Renaming 'Version Template' -> '$FfaVersion'"
    Rename-Item -Path $versionTemplatePath -NewName $FfaVersion
} else {
    $candidate = Join-Path $Cfg.InstallRoot 'Binaries\Version Template'
    if (Test-Path $candidate) {
        New-Item -ItemType Directory -Force -Path $Cfg.BinariesRoot | Out-Null
        Move-Item -Path $candidate -Destination $binariesVersionPath -Force
        Write-Ok "Moved Version Template -> $binariesVersionPath"
    } else {
        Write-Warn "'Version Template' not found - creating empty $binariesVersionPath"
        New-Item -ItemType Directory -Force -Path $binariesVersionPath | Out-Null
    }
}

foreach ($sub in @('Apps', 'DacPacs', 'Plugins', 'Solutions')) {
    $p = Join-Path $binariesVersionPath $sub
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}
Write-Ok "Binaries layout ready: $binariesVersionPath\{Apps, DacPacs, Plugins, Solutions}"

# --- 3. Overlay all-in-one pipeline drop -----------------------------------
$appsFolder = Join-Path $binariesVersionPath 'Apps'
if ((Get-ChildItem $appsFolder -ErrorAction SilentlyContinue) -and -not $BinariesZipPath) {
    Write-Ok "Apps folder is non-empty - assuming pipeline drop already overlaid (skipping). Pass -BinariesZipPath to force re-overlay."
} else {
    Write-Host ''
    Write-Host 'Open a browser and:' -ForegroundColor Yellow
    Write-Host '  1) Go to: https://flintfox.visualstudio.com/FFA/_build'
    Write-Host '  2) Filter pipelines for: all-in-one'
    Write-Host '  3) Click the matching pipeline'
    Write-Host '  4) Pick a run that used the master branch'
    Write-Host '  5) On the Summary tab, under Related, click "1 published; N consumed"'
    Write-Host '  6) Hover the "drop" folder, click the three dots, choose Download artifacts'
    Write-Host ''
    if ([string]::IsNullOrEmpty($BinariesZipPath)) {
        $BinariesZipPath = Read-ZipPath 'Path to downloaded drop.zip'
    } elseif (-not (Test-Path $BinariesZipPath)) {
        Write-Err "BinariesZipPath not found: $BinariesZipPath"
    }

    $tempBin = Join-Path $env:TEMP 'FFA_Drop'
    if (Test-Path $tempBin) { Remove-Item $tempBin -Recurse -Force }
    Write-Log "Extracting $BinariesZipPath -> $tempBin"
    Expand-Archive -Path $BinariesZipPath -DestinationPath $tempBin -Force

    $dropRoot = $tempBin
    if (Test-Path (Join-Path $tempBin 'drop')) { $dropRoot = Join-Path $tempBin 'drop' }

    $expected = @('Apps', 'DacPacs', 'Plugins', 'Solutions', 'Planning')
    $copied = 0
    foreach ($sub in $expected) {
        $src = Join-Path $dropRoot $sub
        if (Test-Path $src) {
            $dst = Join-Path $binariesVersionPath $sub
            if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Force -Path $dst | Out-Null }
            Write-Log "Overlaying $sub -> $dst"
            Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
            $copied++
        } else {
            Write-Warn "Drop did not contain expected folder: $sub"
        }
    }
    if ($copied -eq 0) {
        Write-Err "No expected folders found inside the drop. Drop root contents: $((Get-ChildItem $dropRoot | Select-Object -ExpandProperty Name) -join ', ')"
    }
    Write-Ok "Drop overlaid into $binariesVersionPath ($copied folder(s) copied)"
}

# --- 4. Verify DacPacs ------------------------------------------------------
$dacPacFolder = Join-Path $binariesVersionPath 'DacPacs'
$requiredDacPacs = @(
    'Flintfox.Azara.Data.Config.SQL.dacpac',
    'Flintfox.Azara.Data.Tenant.SQL.dacpac',
    'Flintfox.DataWarehouse.SQL.dacpac',
    'master.dacpac'
)
$missing = @()
foreach ($d in $requiredDacPacs) {
    if (Test-Path (Join-Path $dacPacFolder $d)) {
        Write-Ok "DacPac present: $d"
    } else {
        Write-Warn "DacPac missing: $d"
        $missing += $d
    }
}

if ($missing -contains 'Flintfox.Azara.Data.Config.SQL.dacpac') {
    Write-Host ''
    Write-Host 'Config DacPac missing - get it from the build-config-db-dacpac pipeline:' -ForegroundColor Yellow
    Write-Host '  1) Go to: https://flintfox.visualstudio.com/FFA/_build'
    Write-Host '  2) Filter pipelines for: db-dacpac'
    Write-Host '  3) Click "build-config-db-dacpac"'
    Write-Host '  4) Pick a run that used the master branch'
    Write-Host '  5) Under Related, click "1 published; 1 consumed"'
    Write-Host '  6) Hover "drop", click the three dots, choose Download artifacts'
    Write-Host ''
    if ([string]::IsNullOrEmpty($ConfigDacpacZipPath)) {
        $ConfigDacpacZipPath = Read-ZipPath 'Path to downloaded db-dacpac drop.zip'
    } elseif (-not (Test-Path $ConfigDacpacZipPath)) {
        Write-Err "ConfigDacpacZipPath not found: $ConfigDacpacZipPath"
    }
    $tempCfg = Join-Path $env:TEMP 'FFA_ConfigDacpac'
    if (Test-Path $tempCfg) { Remove-Item $tempCfg -Recurse -Force }
    Expand-Archive -Path $ConfigDacpacZipPath -DestinationPath $tempCfg -Force
    $cfgDac = Get-ChildItem -Path $tempCfg -Recurse -Filter 'Flintfox.Azara.Data.Config.SQL.dacpac' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cfgDac) { Write-Err 'Flintfox.Azara.Data.Config.SQL.dacpac not found in the db-dacpac drop' }
    Copy-Item -Path $cfgDac.FullName -Destination $dacPacFolder -Force
    Write-Ok "Copied Config DacPac into $dacPacFolder"
}

if ($missing -and $missing -notcontains 'Flintfox.Azara.Data.Config.SQL.dacpac') {
    Write-Warn "Still missing: $($missing -join ', ') - check the FFA wiki for which pipeline produces these"
}

Write-Host ''
Write-Host 'Next: run 10-Run-PreInstall.ps1 (configures firewall, generates cert, deploys Config DB)' -ForegroundColor Yellow
