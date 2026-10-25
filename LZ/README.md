# LZ deployments from the jump box

This Terraform root deploys a private, RBAC-enabled Key Vault into the existing
peered VNet, now called the LZ. Run it interactively on the Windows jump box, not
in GitHub Actions. It does not rename, recreate, or manage the existing VNets,
subnets, or peerings.

## Layout and ownership

```text
Local workstation                 Windows jump box
  Edit LZ Terraform   ----------> C:\src\Private-Network-Deployment-Testing
                Git pull or copy                  |
                                                  | terraform -chdir=LZ ...
                                                  v
Jump-box VNet 10.40.0.0/16 <==== existing peering ====> LZ VNet 10.50.0.0/16
  Terraform process                                   Existing peer subnet
        |                                               Key Vault private endpoint
        | DNS                                                  |
        v                                                      v
Azure-provided DNS                                      Private Key Vault
        |
        +-- privatelink.vaultcore.azure.net
            Linked to BOTH VNets; endpoint zone group maintains the A record

VM Terraform state: pndt-vm.tfstate   (owns networks, jump box, Bastion)
LZ Terraform state: pndt-lz.tfstate   (owns vault, endpoint, DNS, vault RBAC)
```

Both VNets must still use Azure-provided DNS for this zone-link design. If DNS
was changed outside this repository, integrate the existing DNS solution first.
No firewall transit or DNS Private Resolver is needed for these directly peered
VNets. The Key Vault itself is a managed service; its private endpoint is in the
LZ subnet.

## 1. Get the code onto the jump box

### Recommended: clone once, then pull each iteration

Use your organization's approved Git authentication on the jump box. Azure SPN
credentials and GitHub Actions secrets do not authenticate Git to a private
GitHub repository. Do not put a Git token in a clone URL.

On the jump box:

```powershell
New-Item -ItemType Directory -Path C:\src -Force
Set-Location C:\src
git clone https://github.com/ulysesramos/Private-Network-Deployment-Testing.git
Set-Location C:\src\Private-Network-Deployment-Testing
```

These changes must first be reviewed, committed, and pushed to an approved branch
before another clone can retrieve them. Nothing in this guide commits or pushes
automatically. For subsequent iterations, edit locally, commit/push the change,
then on the jump box:

```powershell
Set-Location C:\src\Private-Network-Deployment-Testing
git pull --ff-only
```

If using a branch other than the default, check out that branch on the jump box
before pulling. Avoid editing tracked files on both computers at once. Local
variable files, state/cache files, and saved plans are ignored by Git. Commit the
LZ provider lockfile with the code so the jump box installs the same versions.

Pushing LZ-only changes does not run the VM workflow. Changes under `VM`, its
backend file, or the workflow itself can still trigger that workflow on `main`.
Pulling code never applies infrastructure.

### Alternative: copy local files without Git

File copy/paste through Bastion requires its native Windows RDP client, Standard
SKU or higher, and native-client tunneling enabled. The current Bastion Terraform
does not configure those prerequisites; browser-based Bastion does not support
file upload/download. Changing Bastion is a separate infrastructure change.

If native RDP is already enabled, connect from your local workstation:

```powershell
az login
az account set --subscription "<subscription-ID>"
$vmId = az vm show --resource-group "rg-pndt-prod" --name "vm-pndt-prod-iac" --query id -o tsv
az network bastion rdp --name "bas-pndt-prod" --resource-group "rg-pndt-prod" --target-resource-id $vmId
```

In the native RDP session, use file Copy/Paste to transfer the `LZ` folder and
`.tfbackend\lz` into the corresponding repository layout on the jump box. Repeat
for changed source files on later iterations. Copy the provider lockfile too.
Do not copy `.terraform`, state, saved plans, or credentials. Do not delete the
jump box's local variable file when updating source files. Mirror source-file
deletions deliberately so obsolete `.tf` files do not remain active.

See [Bastion native-client file transfer](https://learn.microsoft.com/azure/bastion/vm-upload-download-native).
No public IP, inbound SSH, or inbound public RDP on the VM is needed for Git or
Bastion-based transfer.

## 2. Check tools and prerequisites

In a fresh PowerShell window on the jump box:

```powershell
Get-Command terraform, az, git | Select-Object Name, Source
terraform version
az version
git --version
```

Terraform 1.7 or newer is required. The VM extension attempts installation but
does not reliably report individual installation failures.

The deploying SPN needs:

- Contributor (or equivalent scoped permissions) to create the LZ resource group
  and its resources, plus read/join permissions on the existing networks/subnet.
- Permission to create the vault role assignment, such as Role Based Access
  Control Administrator at a scope covering the new resource group. Contributor
  alone cannot create role assignments.
- Storage Blob Data Contributor on the existing Terraform state container, plus
  network connectivity to that storage account.

The state account/container must already exist. This root does not open the
state account firewall or change its authentication settings. The jump box also
needs outbound access to Azure authentication/management endpoints and Terraform
provider downloads (or an approved mirror), plus HTTPS access to the vault
private endpoint through the existing peering.

This first deployment creates the vault, not secrets or keys. It grants the
actual Terraform caller Key Vault Secrets Officer. To grant access to an SPN,
run Terraform as that SPN. Other workloads require their own role assignments.

The example assumes no existing private DNS zone for this service linked to
these VNets. If your environment already manages that zone, reuse/import it
under an agreed state owner instead of creating a conflicting second zone.

## 3. Authenticate on the jump box

For public Azure, set the SPN credentials in the current PowerShell process:

```powershell
$env:ARM_ENVIRONMENT     = "public"
$env:ARM_CLIENT_ID       = "<SPN-client-ID>"
$env:ARM_TENANT_ID       = "<tenant-ID>"
$env:ARM_SUBSCRIPTION_ID = "<subscription-ID>"
$secret = Read-Host "SPN client secret" -AsSecureString
$env:ARM_CLIENT_SECRET = [System.Net.NetworkCredential]::new("", $secret).Password
Remove-Variable secret

az cloud set --name AzureCloud
az login --service-principal --username $env:ARM_CLIENT_ID --password $env:ARM_CLIENT_SECRET --tenant $env:ARM_TENANT_ID --output none
az account set --subscription $env:ARM_SUBSCRIPTION_ID
```

The Azure CLI login supports the diagnostic commands below; Terraform uses the
`ARM_*` variables. Do not print/store the client secret, and do not reuse
pipeline-only `ARM_ACCESS_KEY` or conflicting backend authentication overrides.
Close the session when finished and run `az logout` if the CLI login should not
remain cached.

For Azure Government, use `ARM_ENVIRONMENT=usgovernment`, CLI cloud
`AzureUSGovernment`, the appropriate backend/subscription values, and set
`key_vault_private_dns_zone_name` to `privatelink.vaultcore.usgovcloudapi.net`.

## 4. Configure and deploy

From the repository root on the jump box:

```powershell
Copy-Item .\LZ\terraform.tfvars.example .\LZ\terraform.tfvars
notepad .\LZ\terraform.tfvars
```

Do this copy only for initial setup. Supply a globally unique vault name and
confirm the network names match the existing deployment (the example uses
`prod`, matching the VM workflow default). The subscription ID must agree with
the authenticated subscription; the backend file separately identifies the
state subscription.

The backend reuses the existing `pndt-vm` container with a distinct blob key:
`pndt-lz.tfstate`. Never initialize the LZ root with `.tfbackend\pndt` or the VM
state key. Keep using this same LZ backend on every iteration; do not copy state
between machines or run concurrent applies.

```powershell
terraform -chdir=LZ init -backend-config="..\.tfbackend\lz"
terraform -chdir=LZ validate
terraform -chdir=LZ plan -out=lz.tfplan
terraform -chdir=LZ apply lz.tfplan
```

Run each command only after the previous command succeeds. Review the plan
before apply. It should add LZ resources and must not replace the existing
networks. No secret/client credential belongs in a `.tfvars` file.

Public access is disabled from creation. RBAC is enabled, trusted-service bypass
is disabled, and purge protection is enabled with 90-day soft-delete retention.
Deleting the vault does not permit immediate reuse of its name; do not use
`terraform destroy` as an iteration/update workflow.

## 5. Validate private access from the jump box

```powershell
$vaultName = terraform -chdir=LZ output -raw key_vault_name
$vaultUri = terraform -chdir=LZ output -raw key_vault_uri
$vaultHost = ([uri]$vaultUri).Host
$expectedIp = terraform -chdir=LZ output -raw key_vault_private_ip

Resolve-DnsName $vaultHost
Test-NetConnection $vaultHost -Port 443
Write-Host "Expected private endpoint IP: $expectedIp"

az keyvault show --name $vaultName --query "{rbac:properties.enableRbacAuthorization,publicAccess:properties.publicNetworkAccess}" -o json
az keyvault secret list --vault-name $vaultName --query "[].id" -o table
```

The final DNS A record must match the endpoint IP, TCP 443 must succeed, RBAC
must be `true`, public access must be `Disabled`, and secret listing must succeed
(an empty list is valid). If DNS is wrong, check both VNet links and the endpoint
zone group. If TCP fails, check endpoint approval, peering, and network rules.
If listing fails with an authorization error, check the CLI identity and allow
for RBAC propagation; do not enable public access to bypass the problem.

## 6. Every subsequent resource/change

1. Add or update Terraform under `LZ` on your workstation.
2. Transfer the code using Git pull or the native RDP copy workflow.
3. Reuse the existing jump-box variable file and LZ backend/state.
4. Run `init` when providers/modules/backend configuration change; run
   `validate`, a new saved `plan`, review, then `apply`.
5. Validate the new resource from the jump box. Never reuse a pre-change plan.

Keep the existing Key Vault resources when adding Storage or other workloads.
Future Terraform secrets/keys require endpoint/DNS readiness and the relevant
data-plane roles; add explicit dependencies on endpoint, zone links, and role
assignments rather than assuming a reference to the vault alone is sufficient.
RBAC/DNS propagation can still take time.

## Offline configuration checks

On a development machine, these checks install providers but do not authenticate
to Azure or create resources. The tests use a mocked AzureRM provider:

```powershell
terraform -chdir=LZ init -backend=false
terraform -chdir=LZ validate
terraform -chdir=LZ test
```

Use a clean development checkout without real `terraform.tfvars` for these tests.
On the deployment jump box, initialize the real backend as described above.
