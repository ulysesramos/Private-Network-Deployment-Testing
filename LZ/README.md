# LZ deployments from the jump box

This Terraform root deploys private services into the existing peered VNet, now
called the LZ. Run it interactively on the Windows jump box, not in GitHub Actions.
It preserves the existing VNets, peer subnet, peerings, and original Key Vault.
It owns a new delegated subnet exclusively for Foundry agent egress.

**Private backend prerequisite:** run [BackendBootstrap](../BackendBootstrap/README.md)
on the jump box first when state storage public access is disabled. It creates
the backend private endpoint and jump-box Blob DNS link using separate local
state. No manual creation/import is required for the inspected environment.

## Resource inventory

GA and REC are association names, not Azure release labels or recovery regions.
All resources inherit the existing LZ VNet's location, including Foundry, which
must be in the same region as its delegated subnet. This expanded stack targets
public Azure; its additional private DNS zone suffixes are not Government-cloud
suffixes.

| Resource | Purpose / association | Private endpoint |
|---|---|---|
| Original Key Vault | Existing deployment, unchanged | Existing vault endpoint |
| Key Vault GA | Additional RBAC vault; purge protection enabled | Vault |
| Storage shared | Standalone general-purpose account | Blob |
| Storage GA | GA project file storage | Blob |
| Storage REC | REC project file storage | Blob |
| Data Lake | Separate StorageV2 account with hierarchical namespace | Blob and DFS |
| Cosmos DB GA | GA project threads, NoSQL API | Sql |
| Cosmos DB REC | REC project threads, NoSQL API | Sql |
| AI Search | Shared by both projects, default Standard SKU | searchService |
| Foundry | One AIServices account, GA and REC projects | account |

Public network access and key authentication are disabled on the new services.
The deployment uses managed identities and Entra-authenticated project
connections. No models or agent application code are deployed; choose a supported
model and obtain quota later before creating/running agents.

## Layout and ownership

```text
Local workstation                 Windows jump box
  Edit LZ Terraform   ----------> C:\src\Private-Network-Deployment-Testing
                Git pull or copy                  |
                                                  | terraform -chdir=LZ ...
                                                  v
Jump-box VNet 10.40.0.0/16 <==== existing peering ====> LZ VNet 10.50.0.0/16
  Terraform process                                   |
        |                                             +-- Existing peer subnet
        | DNS                                         |   (shared services)
        v                                             |   Private endpoints:
Azure-provided DNS                                    |   KV + KV GA
        |                                             |   Storage shared/GA/REC
        +-- Shared private DNS zones                  |   Data Lake Blob + DFS
            Each linked to BOTH VNets                 |   Cosmos GA/REC
            Endpoint zone groups own A records        |   Search + Foundry
                                                      |
                                                      +-- New 10.50.2.0/24
                                                          Foundry egress only
                                                          Microsoft.App/environments
                                                          delegation

One private Foundry account
  +-- GA project identity  --> Storage GA  + Cosmos GA  + shared Search
  +-- REC project identity --> Storage REC + Cosmos REC + shared Search
Each project has its own connections and Agent capability host.

VM Terraform state: pndt-vm.tfstate   (owns networks, jump box, Bastion)
LZ Terraform state: pndt-lz.tfstate   (owns LZ services, endpoints, DNS, RBAC,
                                     projects/capability hosts, egress subnet)
```

Both VNets must still use Azure-provided DNS for this zone-link design. If DNS
was changed outside this repository, integrate the existing DNS solution first.
No firewall transit or DNS Private Resolver is needed for these directly peered
VNets. The Key Vault itself is a managed service; its private endpoint is in the
LZ subnet. All new private endpoints also use this existing peer subnet as shared
services. Do not delegate it or rename it. The separate Foundry egress subnet
must not contain private endpoints.

### DNS zones

The Blob zone is read from the existing `rg-pndt-prod-storage` resource group,
not created by LZ. Override `blob_private_dns_resource_group_name` if needed.
Its existing LZ link stays externally managed; BackendBootstrap owns its new
jump-box link. LZ owns the six other new service zones and their twelve links,
plus the original vault zone/links. Do not create a duplicate Blob zone. If an
older LZ state already owns Blob zones/links, follow the ownership warning in the
bootstrap guide before applying.

| Service | Zone(s), linked to the LZ and jump-box VNets |
|---|---|
| Both Key Vaults | `privatelink.vaultcore.azure.net` (existing managed zone) |
| Blob / Data Lake | `privatelink.blob.core.windows.net`, `privatelink.dfs.core.windows.net` |
| Cosmos NoSQL | `privatelink.documents.azure.com` |
| AI Search | `privatelink.search.windows.net` |
| Foundry | `privatelink.cognitiveservices.azure.com`, `privatelink.services.ai.azure.com`, `privatelink.openai.azure.com` |

### Foundry identity and isolation

Each project gets a system-assigned identity, its own Storage and Cosmos DB
connections, and a connection to shared Search. The Agent capability host
references those project connections. Foundry provisions the agent containers
and databases; do not duplicate them as Terraform-managed containers/databases.

Search connection names must be distinct across projects in this Foundry account.
GA retains its existing Search-service-name connection; REC uses that name with
`-rec` appended. Both connections still target the same Search service. Capability
hosts reference the connection names, not the Search service name directly.

If a previous apply failed creating `rec-search` with "can only be updated by the
workspace that created it", pull this fix and generate a fresh plan. Do not
delete/import GA's connection into REC or recreate the projects. The successful
GA resources remain in state; the missing REC connection should be added on retry.

Each project identity receives:

- Storage Blob Data Owner on its own account (includes data access and
  agent-container ACL/tag operations); no permissions on the other project's account.
- Cosmos DB Operator and Cosmos DB Built-in Data Contributor on its own account.
- Search Index Data Contributor and Search Service Contributor on shared Search.
- Foundry User on the parent account for project-to-Foundry access. The stable
  built-in role ID is used because this role was formerly named Azure AI User.

Sharing Search means those service-level roles can access/manage indexes across
the service. Both projects also share the Foundry account and account-level
Foundry permissions. GA/REC are association labels, not hard security boundaries.
Use separate Foundry/Search services if strict isolation is required. REC is not cross-region disaster
recovery; these are two named projects in the same Foundry account and region.
The original vault, GA vault, shared Storage, and Data Lake are standalone:
Foundry is not automatically given access to them.

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
  and services, read all existing LZ subnets, join the shared-services subnet,
  create the new delegated subnet, and link both existing VNets to DNS zones.
- Permission to create the role assignments, such as Role Based Access
  Control Administrator at a scope covering the new resource group. Contributor
  alone cannot create role assignments.
- Storage Blob Data Contributor on the existing Terraform state container, plus
  network connectivity to that storage account.

The state account/container must already exist. This root does not open the
state account firewall or change its authentication settings. The jump box also
needs outbound access to Azure authentication/management endpoints and Terraform
provider downloads (or an approved mirror), plus HTTPS access to the vault
private endpoint through the existing peering.

The actual Terraform caller receives Key Vault Secrets Officer on both vaults,
Storage Blob Data Contributor on the four new storage accounts, and Foundry
User on both Foundry projects. To grant access to an SPN, run Terraform as that
SPN. Other workloads require their own role assignments.

Before deploying, ensure the subscription permits and has registered
`Microsoft.CognitiveServices`, `Microsoft.App`, `Microsoft.Search`,
`Microsoft.DocumentDB`, `Microsoft.Storage`, and `Microsoft.Network`. For example:

```powershell
az provider register --namespace Microsoft.App --wait
```

Verify regional support, subscription restrictions, and quota for Foundry agents,
Cosmos DB and paid Search. Each Cosmos account must allow at least 3000 RU/s total
throughput for agent provisioning; no low account throughput cap is set here.
Foundry may create chargeable throughput as part of provisioning. Search Standard
has ongoing charges even without models, and private endpoints/storage also
incur charges. LRS storage and single-region Cosmos are test defaults, not a
production availability or disaster-recovery design.

The default egress CIDR is `10.50.2.0/24`. Confirm it is free inside your actual LZ
VNet. Terraform rejects it if it is outside the VNet or overlaps another existing
LZ subnet. Do not create the same subnet in the VM Terraform root: the VM root
owns the VNet and original subnet; the LZ root owns this new standalone subnet.
Do not add inline subnets to the VM root's VNet definition.

The AzureRM `storage.data_plane_available=false` feature intentionally uses
management-plane account operations without initial Blob/Queue availability
checks. This avoids creating a dependency cycle where a new private account
must be reachable before Terraform can create its endpoint. This does not bypass
runtime authorization or backend access checks. No `static_website` or
`queue_properties` blocks are used with this setting.

The example assumes no separately managed private DNS zones for these services linked to
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

The original Key Vault variable supports a Government suffix, but the expanded
Foundry/services stack has not been configured or verified for Azure Government.
Do not use the expanded example there without adapting service availability,
API versions, endpoints, and all private DNS zones.

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
state subscription. Existing users should merge these new values into their
current ignored `terraform.tfvars`, not overwrite their original vault name:

```hcl
resource_suffix           = "your1234"
foundry_egress_subnet_cidr = "10.50.2.0/24"
search_sku                = "standard"
```

Choose a globally unique, stable 4-8 character lowercase alphanumeric suffix.
Changing it later renames/replaces new services. Keep `key_vault_name` and
existing network values unchanged so the original vault/endpoint are preserved.

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
networks or the original vault/endpoint. No secret/client credential belongs in
a `.tfvars` file.

The first expanded apply includes an explicit two-minute RBAC propagation wait
before capability-host provisioning. This is not a guarantee of propagation:
if Azure returns an authorization/provisioning error, inspect the role and
identity, allow propagation, and generate a new plan before retrying. Do not
enable public access. Capability-host provisioning may take much longer than a
normal resource creation; its create/update timeout is one hour.

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

Test all new service hostnames too:

```powershell
$services = terraform -chdir=LZ output -json private_service_uris | ConvertFrom-Json
foreach ($service in $services.PSObject.Properties) {
    $hostname = ([uri]$service.Value).Host
    Write-Host "$($service.Name): $hostname"
    Resolve-DnsName $hostname
    Test-NetConnection $hostname -Port 443
}

terraform -chdir=LZ output -json service_private_endpoints
terraform -chdir=LZ output -json foundry_projects
```

Confirm each hostname's final A record matches that service's endpoint IP(s) and
TCP 443 succeeds. Cosmos can have multiple endpoint IPs (global and regional);
the output shows the primary IP, not every DNS record. DNS/TCP success is not
an application authorization test. Confirm both capability hosts report
`Succeeded`, then deploy a supported model and create/run a test agent in each
project from a client/browser with private network access. Check that GA writes
only to GA Storage/Cosmos, REC writes to REC, and file-search tools can use the
shared Search service. Models and live agent tests are intentionally not included
in Terraform's offline mocked tests.

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

## References

- [Foundry private networking](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Microsoft's BYO-VNet Standard Agent Terraform sample](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-terraform/15b-private-network-standard-agent-setup-byovnet)
- [Standard Agent dependencies and roles](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup)
- [Project capability-host API](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-05-01/accounts/projects/capabilityhosts)

The AzAPI child resources use the stable `2026-05-01` API, the newest stable
version recognized by the installed AzAPI provider's embedded schema. Validation
remains enabled; the implementation does not disable schema checks to use a
newer unrecognized API.

## Offline configuration checks

On a development machine, these checks install providers but do not authenticate
to Azure or create resources. The tests use a mocked AzureRM provider:

```powershell
terraform -chdir=LZ init -backend=false
terraform -chdir=LZ validate
terraform -chdir=LZ test
```

Tests cover the original vault, private-only services, GA/REC connection/identity
wiring, endpoint and DNS layout, and invalid/overlapping egress CIDRs.
Use a clean development checkout without real `terraform.tfvars` for these tests.
On the deployment jump box, initialize the real backend as described above.
