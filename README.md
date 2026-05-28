# FFAScripts

This repository contains two sets of scripts that work in sequence to stand up a new FFA environment.

The first set of scripts is a template to create a test environment, most installations will not use these scripts as they will have their own Azure Instances or On-Prem machines. 

---

## Overview

```
ffa-install-scripts/
├── 01-...sh  through  09-...sh    ← Azure CLI scripts  (run from your local machine)
├── config.env                     ← Shared Azure configuration
│
├── ffa-vm-install-scripts/        ← PowerShell scripts (run inside the VM)
│   ├── config.ps1
│   └── 01-...ps1  through  99-Run-All.ps1

```

---

## Part 1 — Azure CLI Scripts (Provision the VM)

**Location:** root folder (`01-...sh` through `09-...sh`)
**Where to run:** your local machine with access to an Azure Subscription or Azure Cloud Shell
**Purpose:** Create all Azure resources needed to host the FFA application — networking, security rules, the Windows Server VM, and a SQL backend.
**Background** If you are unfamiliar with Azure Cloud Shell, read this [tutorial](https://learn.microsoft.com/en-us/azure/cloud-shell/get-started/classic?tabs=azurecli) first 

### Prerequisites

- Azure CLI installed and logged in (`az login`)
- Bash shell (Linux, macOS, or WSL on Windows)
- Sufficient Azure quota for the VM size you select

### Configuration

Copy or edit `config.env` to set your resource group name, VM name, location, and other environment-specific values before running any script.
Upload all cli the scripts to an Azure Cloud Shell 

### Running the scripts

Run them in order. Each script is idempotent — it skips creation if the resource already exists, so it is safe to re-run.

```bash
./01-Create-ResourceGroup.sh
./02-Create-VNet.sh
./03-Create-NSG.sh
# ... continue in sequence ...
./07-create-vm.sh
```

When `07-create-vm.sh` completes, the Windows Server VM is running in Azure and `config.ps1` has been copied to `C:\projects\ffa\installs\` on the VM automatically.

The script '10-create-sql-server.sh' is optional run this script if you don't have SQL Server,  if you already have SQL Server don't run it

---

## Part 2 — VM Install Scripts (Install FFA on the Machine)

**Location:** `ffa-vm-install-scripts/`

**Where to run:** inside the Windows Server VM, as Administrator

**Purpose:** Install and configure all FFA components — IIS, .NET 8, URL Rewrite, SQL backend, SSL certificate, FFA binaries, and tenant configuration.

### Getting the scripts onto the VM

Copy the  `config.ps1` script onto the C: drive, run it in powershell and it will create the folder location for you. 
Copy the scripts manually to the folder at: 

```
C:\projects\ffa\installs\
```

### Configuration

`config.ps1` is shared across all step scripts. It reads environment variables first and falls back to sensible defaults. Edit defaults in `config.ps1` or export variables before running if you need to override paths, versions, or URLs.

### Running the scripts

Open PowerShell **as Administrator** on the VM and run the scripts in order, or use the wrapper to run all steps unattended:

```powershell
# Run all steps in sequence
.\99-Run-All.ps1

# Or run individual steps
.\01-Configure-IIS.ps1
.\02-Install-DotNet.ps1
.\03-Install-UrlRewrite.ps1
.\04-Install-Sql.ps1
.\05-Verify-Prerequisites.ps1
.\06-Import-SSL-Certificate.ps1 -- this step is optional if you already have a certificate
.\07-Download-Installer.ps1
.\08-Configure-Tenant-Json.ps1
.\09-Setup-Binaries.ps1
.\10-Run-PreInstall.ps1

```

Each script dot-sources `config.ps1` at the start and logs its progress to the console with timestamps.

When you finish with these scripts they will take you to a different set of scripts maintained by the Engineering team for installation purposes. 

---
