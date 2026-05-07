# FFA Azure Provisioning — Independent `az` CLI Scripts

This folder is a decomposition of `ffa-powershell-scripts.ps1` into independently runnable Azure CLI (bash) scripts. Each script creates **one** Azure resource (or performs one Azure-side action) so that any individual step can be re-run, retried, or wired into its own pipeline stage.

## Source mapping

| Original PS1 function | What it did | Where it lives now |
|----------------------|-------------|--------------------|
| `Invoke-Script01-ProvisionVM` | Created RG + VNet/Subnet + NSG (with 5 rules) + PIP + NIC + VM in a single function | Split into **scripts 01–07** |
| `Invoke-Script06-RebootVM` | Restart the VM via Azure, poll until back online, run verification commands | Split into **scripts 08–09** |
| `Invoke-Script02..05, 07, 08` (IIS, prereqs, FFA ports, SSL import, FFA download, JSON config) | OS-level configuration **inside** the VM | **Not converted** — these don't create Azure resources. They remain PowerShell and would be invoked from a pipeline via `az vm run-command invoke` (see "Running in-VM scripts" below). |

## Files

| File | Resource / Action | Re-runnable? |
|------|-------------------|--------------|
| `config.env` | Shared variables (sourced by every script) | n/a |
| `00-prereqs.sh` | `az` login + subscription set | yes |
| `01-create-resource-group.sh` | Resource Group | yes (idempotent) |
| `02-create-vnet-subnet.sh` | Virtual Network + Subnet | yes |
| `03-create-nsg.sh` | Network Security Group (empty) | yes |
| `04-create-nsg-rules.sh` | 5 NSG inbound rules (HTTP, HTTPS, FFA-App, SQL, RDP) | yes (upserts each rule) |
| `05-create-public-ip.sh` | Standard Static Public IP | yes |
| `06-create-nic.sh` | NIC bound to subnet + PIP + NSG | yes |
| `07-create-vm.sh` | Windows Server 2025 VM | yes |
| `08-restart-vm.sh` | Restart VM + poll until running | yes |
| `09-verify-vm.sh` | Run-command checks (IIS, .NET, ANCM, URL Rewrite) | yes |
| `99-deploy-all.sh` | Convenience runner (calls 00–07 in order) | yes |

## Why split it this way?

The original `Invoke-Script01-ProvisionVM` was monolithic — one function, six resources. Splitting it gives you:

- **Independent re-runs.** If only the NIC fails, you re-run `06`, not the whole VM build.
- **Pipeline-friendly stages.** Each `.sh` becomes a discrete Azure DevOps / GitHub Actions step with its own gate, output, and retry policy.
- **Cleaner separation of concerns.** NSG creation and NSG rules are split (`03` vs `04`) so port changes don't require touching the NSG itself. This matters because the FFA app port list is the most frequently edited item in this stack.
- **Idempotency by design.** Every script checks for existence before creating, so partial failures don't corrupt state. Re-running `99-deploy-all.sh` is safe.
- **Independent identity / RBAC.** Each step can run under a least-privileged service principal (e.g. networking SP for 02–06, compute SP for 07).

## Running

```bash
# 1. Edit shared variables (or override via env)
vi config.env

# 2. Pull secrets out of band — never commit these
export VM_ADMIN_PASSWORD="$(az keyvault secret show \
    --vault-name kv-flintfox-prod-aue-01 \
    --name vm-admin-password --query value -o tsv)"

# 3. Run the lot — or any individual script
bash 99-deploy-all.sh
# ...or just one:
bash 04-create-nsg-rules.sh
```

## Running the in-VM scripts (Scripts 02–05, 07, 08 from the PS1)

These remain PowerShell because they configure the OS, not Azure. Push them via `run-command` once the VM is up:

```bash
az vm run-command invoke \
  --resource-group "${RG}" --name "${VM_NAME}" \
  --command-id RunPowerShellScript \
  --scripts @../ffa-powershell-scripts.ps1 \
  --parameters "Invoke-Script02-ConfigureIISFirewall"
```

(or extract each `Invoke-ScriptNN-*` function into its own `.ps1` so each can be pushed separately — same decomposition pattern, on the OS side.)

## Idempotency strategy

Each script uses one of two patterns:

1. **Show-then-create.** `az <resource> show ...` — if it returns success, skip; otherwise create.
2. **Upsert command.** `az network nsg rule create` overwrites by name, so it's safe to re-run.

`az group create`, `az vm run-command invoke`, and `az vm restart` are themselves idempotent.

## Secret handling

`VM_ADMIN_PASSWORD` and any SQL credentials must come from Azure Key Vault, not from `config.env`. The pattern shown in `07-create-vm.sh` and the README is the only supported way. The original PS1 had `Get-Credential` interactive prompts, which break in a pipeline — Key Vault is the equivalent.

## Suggested pipeline stages

Wire the scripts into Azure DevOps roughly like this:

```
[ Login + Subscription ]   00-prereqs.sh
        ↓
[ Resource Group ]          01-create-resource-group.sh
        ↓
[ Networking ]              02 → 03 → 04 → 05  (can run 02/03 in parallel; 04 needs 03; 05 is independent)
        ↓
[ NIC ]                     06-create-nic.sh
        ↓
[ Compute ]                 07-create-vm.sh
        ↓
[ In-VM Config ]            run-command pushes for PS Scripts 02→03→04→05
        ↓
[ Restart + Verify ]        08-restart-vm.sh → 09-verify-vm.sh
        ↓
[ FFA Install ]             run-command pushes for PS Scripts 07→08, then InstallFFA.ps1
```

Each `↓` is a pipeline gate that fails the run on a non-zero exit code.

## What this isn't

- **Not Bicep / Terraform.** This is a deliberate procedural decomposition — useful for diagnosis and pipeline composition, not for desired-state IaC. If you also want IaC, treat these scripts as the executable spec and port them to Bicep modules.
- **Not the in-VM bits.** Anything inside the OS (IIS, .NET, FFA binaries, `Installation.{VmName}.json`) is still PowerShell — converting it to bash gains you nothing on a Windows VM.
