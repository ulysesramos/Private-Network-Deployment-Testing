# Private backend bootstrap

Run this Terraform root on the jump box before initializing LZ. Its local backend
does not require access to the blocked Blob endpoint. It still requires Azure
management API access and permission to create/approve private endpoints, join
the LZ subnet, read the existing resources, and link the existing DNS zone to the
jump-box VNet. Blob data access still requires Storage Blob Data Contributor.

## What it owns

```text
Jump box -- existing peering --> LZ shared-services subnet
                                   |
                                   +-- NEW backend Blob private endpoint
                                                  |
                                                  v
                                            pndtterrastate
                                            Public access stays Disabled

EXISTING privatelink.blob.core.windows.net zone (rg-pndt-prod-storage)
  +-- Existing LZ VNet link: untouched
  +-- NEW jump-box VNet link: owned by BackendBootstrap
  +-- Backend A record: maintained by new endpoint DNS zone group
```

Only the endpoint (including its DNS zone group) and jump-box link are created.
The existing zone, storage account, LZ link, subnets, policy, account settings,
and Blob data are not taken over or changed. LZ reads the shared Blob zone and
continues to own the other service zones. Both VNets must use Azure-provided DNS
or an equivalent configured resolver.

Defaults in [variables.tf](variables.tf) match the inspected environment.
Optional overrides belong in this folder's ignored `terraform.tfvars`, not the
LZ variable file.

## 1. Get the code and authenticate

After review, commit/push the source changes, then pull the same branch on the
jump box (or copy the updated source files). No commit/push is automatic.

```powershell
Set-Location C:\Private-Network-Deployment-Testing
git pull --ff-only
az account show --query "{identity:user.name,subscription:id}" -o table
```

Use your intended Azure user or SPN. Azure CLI login does not override `ARM_*`
SPN credentials. Do not print secrets. Do not run the VM workflow as a workaround:
it attempts to open public storage access, contrary to the enforced policy.

## 2. Bootstrap with local state

```powershell
terraform -chdir=BackendBootstrap init
terraform -chdir=BackendBootstrap validate
terraform -chdir=BackendBootstrap test
terraform -chdir=BackendBootstrap plan -out=backend.tfplan
terraform -chdir=BackendBootstrap apply backend.tfplan
```

Run each command only after the previous succeeds. Review the plan before apply:
expect two resource additions and no changes/deletions to existing resources.
Endpoint creation must result in an Approved connection.

**Securely back up `BackendBootstrap\terraform.tfstate` and its backup after apply.**
They are ignored by Git. Keep this local state persistently on the jump box.
Never apply this root elsewhere with empty state, delete its state, or move these
resources into LZ state. Both resources have `prevent_destroy`; removing their
configuration also removes that protection. Do not destroy the bootstrap, since
that can strand access to both VM and LZ state.

The bootstrap needs no manual resource creation or import for the environment
inspected before this change.

## 3. Verify on the jump box

```powershell
Clear-DnsClientCache
terraform -chdir=BackendBootstrap output -raw backend_private_ip
Resolve-DnsName pndtterrastate.blob.core.windows.net
Test-NetConnection pndtterrastate.blob.core.windows.net -Port 443
az network private-endpoint show --resource-group pndt-terraform-state --name pe-pndtterrastate-blob --query "privateLinkServiceConnections[].privateLinkServiceConnectionState" -o json
az storage blob list --account-name pndtterrastate --container-name pndt-vm --auth-mode login --num-results 1 --query "[].name" -o table
az storage account show --name pndtterrastate --resource-group pndt-terraform-state --query publicNetworkAccess -o tsv
```

The final DNS A record must match the private endpoint IP, TCP 443 must succeed,
the connection must be Approved, Blob listing must succeed, and public access
must remain Disabled. DNS propagation can take time. If CLI succeeds but Terraform
fails, check its authentication environment and cached backend configuration.
Keep the normal Blob hostname; do not substitute the private IP in backend config.

## 4. Initialize LZ, then review and apply

```powershell
terraform -chdir=LZ init -reconfigure -backend-config="..\.tfbackend\lz"
terraform -chdir=LZ state list
terraform -chdir=LZ validate
terraform -chdir=LZ plan -var-file="terraform.tfvars" -out=lz.tfplan
terraform -chdir=LZ apply lz.tfplan
```

The LZ variable `blob_private_dns_resource_group_name` defaults to
`rg-pndt-prod-storage`. Preserve all existing variable values. The shared Blob
zone, existing links and backend endpoint should not be created/replaced/destroyed
in the LZ plan.

## Existing manual resources or previous LZ state

If someone has since created the endpoint or jump-box link, stop before apply.
Identify its owner. Do not manage a resource in two Terraform states. If truly
unmanaged, import only the existing resource into bootstrap local state, using
its actual ID/name and matching the configuration to that name:

```powershell
terraform -chdir=BackendBootstrap import azurerm_private_endpoint.backend_blob "/subscriptions/92ade028-994d-424c-a639-48e33b16e332/resourceGroups/pndt-terraform-state/providers/Microsoft.Network/privateEndpoints/pe-pndtterrastate-blob"
terraform -chdir=BackendBootstrap import azurerm_private_dns_zone_virtual_network_link.jumpbox_blob "/subscriptions/92ade028-994d-424c-a639-48e33b16e332/resourceGroups/rg-pndt-prod-storage/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/backend-jumpbox-blob-link"
```

Do not import the existing zone or LZ link; both remain externally owned.

If `LZ state list` contains `azurerm_private_dns_zone.services["blob"]` or
`azurerm_private_dns_zone_virtual_network_link.services["blob-lz"]` /
`["blob-jumpbox"]`, do not apply a plan deleting those resources. Back up state,
inspect their actual IDs and endpoint references, and plan an explicit ownership
transfer before applying this change. Do not blindly remove state or delete a
zone/link to resolve a conflict.

The private endpoint does not give GitHub-hosted runners access. The existing VM
workflow still needs an approved private connectivity/execution design.

## Offline validation

`terraform test` uses a mocked provider and plans only; it creates no Azure
resources. It does not verify live DNS, routing, policy or RBAC.
