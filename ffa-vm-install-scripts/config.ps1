# =============================================================================
#  FFA In-VM Install - shared configuration
#  Dot-source from any of the step scripts:
#      . ./config.ps1
#  These scripts run INSIDE the Windows VM, as Local Administrator.
# =============================================================================

$Cfg = [ordered]@{}

# --- FFA version & locations -------------------------------------------------
$Cfg.FfaVersion       = if ($env:FFA_VERSION)        { $env:FFA_VERSION }        else { '6.9.2' }
$Cfg.InstallRoot      = if ($env:FFA_INSTALL_ROOT)   { $env:FFA_INSTALL_ROOT }   else { 'C:/projects/ffa/installs' }
$Cfg.BinariesRoot     = if ($env:FFA_BINARIES_ROOT)  { $env:FFA_BINARIES_ROOT }  else { 'C:/projects/ffa/installs/Binaries' }
$Cfg.PrereqsTempDir   = if ($env:FFA_PREREQS_TEMP)   { $env:FFA_PREREQS_TEMP }   else { 'C:/projects/ffa/installs/Prereqs' }
$Cfg.ScriptsZipUrl    = if ($env:FFA_SCRIPTS_URL)    { $env:FFA_SCRIPTS_URL }    else { 'https://ffainstalls.blob.core.windows.net/ffa-releases/FFA/FFA Install.zip' }

# --- FFA Windows install paths (do not change unless agreed with Flintfox) ---
$Cfg.PlatformWebRoot      = if ($env:FFA_PLATFORM_WEB_ROOT)     { $env:FFA_PLATFORM_WEB_ROOT }     else { 'C:\Program Files\Flintfox International\RMx Web Application' }
$Cfg.OdataWebRoot         = if ($env:FFA_ODATA_WEB_ROOT)        { $env:FFA_ODATA_WEB_ROOT }        else { 'C:\Program Files\Flintfox International\RMx oData Application' }
$Cfg.PlatformServiceRoot  = if ($env:FFA_PLATFORM_SERVICE_ROOT) { $env:FFA_PLATFORM_SERVICE_ROOT } else { 'C:\Program Files\Flintfox International\RMx Service Application' }

# --- FFA app ports (must match NSG rules in the Azure scripts) ---------------
$Cfg.FfaAppPorts = @(444, 446, 5001, 5002, 8005, 8006, 9000, 9001)

# --- .NET --------------------------------------------------------------------
$Cfg.DotnetTargetVersion = if ($env:DOTNET_TARGET_VERSION) { $env:DOTNET_TARGET_VERSION } else { '8.0.16' }
$Cfg.DotnetReleasesJson  = 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/8.0/releases.json'
$Cfg.DotnetInstallScriptUrl = 'https://dot.net/v1/dotnet-install.ps1'

# --- IIS URL Rewrite 2.1 (stable URL since 2014) -----------------------------
$Cfg.UrlRewriteMsiUrl    = 'https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi'

# --- SQL Server backend ------------------------------------------------------
# 'Local' = install SQL Server 2022 Express on the VM
# 'Azure' = skip local install, expect connection string in 08-Configure-Tenant-Json (default)
$Cfg.SqlBackend          = if ($env:SQL_BACKEND)          { $env:SQL_BACKEND }          else { 'Azure' }
$Cfg.SqlInstallerUrl     = if ($env:SQL_INSTALLER_URL)    { $env:SQL_INSTALLER_URL }    else { 'https://go.microsoft.com/fwlink/p/?linkid=2216019' }
$Cfg.SqlInstanceName     = if ($env:SQL_INSTANCE)         { $env:SQL_INSTANCE }         else { 'SQLEXPRESS' }
$Cfg.SqlSaPassword       = $env:SQL_SA_PASSWORD

# --- SQL Server Management Studio (SSMS 22) ---------------------------------
# Always installed alongside SQL (small, useful, no prompt). Override with
# $env:SSMS_INSTALLER_URL or $env:SKIP_SSMS=1 to skip.
$Cfg.SsmsInstallerUrl    = if ($env:SSMS_INSTALLER_URL)   { $env:SSMS_INSTALLER_URL }   else { 'https://aka.ms/ssms/22/release/vs_SSMS.exe' }
$Cfg.SkipSsms            = ($env:SKIP_SSMS -eq '1')

# --- Visual Studio Code ------------------------------------------------------
# Always installed unless $env:SKIP_VSCODE=1 is set.
$Cfg.VsCodeInstallerUrl  = if ($env:VSCODE_INSTALLER_URL) { $env:VSCODE_INSTALLER_URL } else { 'https://update.code.visualstudio.com/latest/win32-x64-user/stable' }
$Cfg.SkipVsCode          = ($env:SKIP_VSCODE -eq '1')

# --- Shared helpers ----------------------------------------------------------
function Write-Log { param([string]$Message) Write-Host ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $Message) -ForegroundColor Cyan }
function Write-Ok  { param([string]$Message) Write-Host ("[OK]  {0}" -f $Message) -ForegroundColor Green }
function Write-Warn{ param([string]$Message) Write-Host ("[WARN] {0}" -f $Message) -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host ("[ERR] {0}" -f $Message) -ForegroundColor Red; exit 1 }

function Assert-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($current)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Err 'This script must be run as Administrator. Right-click PowerShell -> Run as Administrator.'
    }
}

# Verify a downloaded artifact has a valid Authenticode signature signed by
# Microsoft. Apply to every installer/script before executing.
function Assert-MicrosoftSigned {
    param([Parameter(Mandatory)][string]$Path)
    $sig = Get-AuthenticodeSignature -FilePath $Path
    if ($sig.Status -ne 'Valid') {
        Write-Err "Invalid Authenticode signature on '$Path': $($sig.Status)"
    }
    if ($sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        Write-Err "File '$Path' is signed but not by Microsoft (signer: $($sig.SignerCertificate.Subject))"
    }
}

function Invoke-WebDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [int]$Retries = 3
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
            return
        } catch {
            Write-Warn "Attempt $i/$Retries failed: $($_.Exception.Message)"
            if ($i -lt $Retries) { Start-Sleep -Seconds (5 * $i) }
        }
    }
    Write-Err "Download failed after $Retries attempts: $Url"
}

function Initialize-FfaDirectories {
    $paths = @($Cfg.InstallRoot, $Cfg.BinariesRoot, $Cfg.PrereqsTempDir)
    foreach ($p in $paths) {
        if (-not (Test-Path -Path $p -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $p -Force | Out-Null
                Write-Ok "Created directory: $p"
            } catch {
                Write-Err "Failed to create directory '$p': $($_.Exception.Message)"
            }
        }
    }
}

Initialize-FfaDirectories
Set-Location C:\projects\ffa\installs\

Write-Host 'Next: Copy the vm install scripts to the target machine on this folder' -ForegroundColor Yellow
Write-Host 'Then run the scripts in order, starting with 01-Install-Prereqs.ps1' -ForegroundColor Yellow
