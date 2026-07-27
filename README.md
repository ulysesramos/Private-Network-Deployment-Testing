# Private Network Deployment Testing

This repository deploys a Windows VM behind Azure Bastion in a private VNet, with a peered private network for deployment testing.

## Terraform Backend Authentication Type

The Terraform state backend is `azurerm` (configured in `VM/main.tf` and `.tfbackend/pndt`).

Authentication type in this repo:
- **Service Principal (SPN) with client secret** via environment variables (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`).
- Backend access is expected through **Azure AD/RBAC** permissions to the storage account container.

Notes:
- The workflow also enables shared key access on the storage account for compatibility, but the backend config does not pass an explicit storage account key.
- Required backend metadata is in `.tfbackend/pndt` (`resource_group_name`, `storage_account_name`, `container_name`, `key`, `subscription_id`).

## SPN Creation (Azure CLI)

The workflow targets Azure Government. Use the command block that matches your terminal.

### PowerShell (pwsh) - recommended for this repo on Windows

```powershell
# 1) Target Azure Government and login
az cloud set -n AzureUSGovernment
az login

# 2) Set values
$SUB_ID = "92ade028-994d-424c-a639-48e33b16e332"
$RG_NAME = "pndt-terraform-state"
$SA_NAME = "pndtterrastate"
$CONTAINER_NAME = "pndt-vm"
$SP_NAME = "sp-pndt-terraform"
$LOCATION = "centralus"

# 3) Ensure the right subscription context
az account set --subscription $SUB_ID

# 4) Create SPN with Contributor at subscription scope
$SP_JSON = az ad sp create-for-rbac --name $SP_NAME --role Contributor --scopes "/subscriptions/$SUB_ID" --sdk-auth
Write-Output $SP_JSON

# 5) Extract identifiers
$SP = $SP_JSON | ConvertFrom-Json
$APP_ID = $SP.clientId
$TENANT_ID = $SP.tenantId
$OBJECT_ID = az ad sp show --id $APP_ID --query id -o tsv

# 6) Deploy backend resource group
az group create --name $RG_NAME --location $LOCATION

# 7) Deploy backend storage account and container
az storage account create --name $SA_NAME --resource-group $RG_NAME --location $LOCATION --sku Standard_LRS --kind StorageV2
az storage container create --name $CONTAINER_NAME --account-name $SA_NAME --auth-mode login

# 8) Build storage scopes
$STORAGE_ID = az storage account show --name $SA_NAME --resource-group $RG_NAME --query id -o tsv
$CONTAINER_SCOPE = "$STORAGE_ID/blobServices/default/containers/$CONTAINER_NAME"

# 9) Grant backend access roles
az role assignment create --assignee-object-id $OBJECT_ID --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $CONTAINER_SCOPE
az role assignment create --assignee-object-id $OBJECT_ID --assignee-principal-type ServicePrincipal --role "Storage Account Contributor" --scope $STORAGE_ID
```

### Bash (Cloud Shell, WSL, Git Bash)

```bash
# 1) Target Azure Government and login
az cloud set -n AzureUSGovernment
az login

# 2) Set values
SUB_ID="92ade028-994d-424c-a639-48e33b16e332"
RG_NAME="pndt-terraform-state"
SA_NAME="pndtterrastate"
CONTAINER_NAME="pndt-vm"
SP_NAME="sp-pndt-terraform"
LOCATION="centralus"

# 3) Ensure the right subscription context
az account set --subscription "$SUB_ID"

# 4) Create SPN with Contributor at subscription scope
SP_JSON=$(az ad sp create-for-rbac --name "$SP_NAME" --role Contributor --scopes "/subscriptions/$SUB_ID" --sdk-auth)
echo "$SP_JSON"

# 5) Extract identifiers
APP_ID=$(echo "$SP_JSON" | jq -r .clientId)
TENANT_ID=$(echo "$SP_JSON" | jq -r .tenantId)
OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

# 6) Deploy backend resource group
az group create --name "$RG_NAME" --location "$LOCATION"

# 7) Deploy backend storage account and container
az storage account create --name "$SA_NAME" --resource-group "$RG_NAME" --location "$LOCATION" --sku Standard_LRS --kind StorageV2
az storage container create --name "$CONTAINER_NAME" --account-name "$SA_NAME" --auth-mode login

# 8) Build storage scopes
STORAGE_ID=$(az storage account show \
  --name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --query id -o tsv)
CONTAINER_SCOPE="$STORAGE_ID/blobServices/default/containers/$CONTAINER_NAME"

# 9) Grant backend access roles
az role assignment create \
  --assignee-object-id "$OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$CONTAINER_SCOPE"

az role assignment create \
  --assignee-object-id "$OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Account Contributor" \
  --scope "$STORAGE_ID"
```

If jq is not installed in Bash, you can parse values using --query directly from separate az calls.

## GitHub Secrets Requirements

Create these repository secrets:

- `AZURE_P_PNDT_SPN`
  - JSON from `az ad sp create-for-rbac --sdk-auth`.
  - Used by `azure/login`.
- `AZURE_P_PNDT_SPN_CLIENT_ID`
  - SPN application (client) ID.
- `AZURE_P_PNDT_SPN_CLIENT_SECRET`
  - SPN client secret.
- `AZURE_PNDT_TENANT_ID`
  - Microsoft Entra tenant ID.
- `PNDT_VM_ADMIN_USERNAME`
  - Windows VM local admin username.
- `PNDT_VM_ADMIN_PASSWORD`
  - Windows VM local admin password.

You can populate these values with [scripts/populate-github-secrets.ps1](scripts/populate-github-secrets.ps1) after installing and authenticating the GitHub CLI. If you run it from inside the cloned repo, it can auto-detect the repository from the local Git `origin` remote.

## GitHub Variables Requirements

Create these repository variables:

- `AZURE_P_PNDT_SUB_ID`
  - Subscription used by Terraform provider, deployment resources, and Terraform state storage account.

## Optional Hardening

For better security, consider:
- Switching from client secret auth to GitHub OIDC federated credentials.
- Removing the storage account shared key enablement once Azure AD data plane auth is fully validated.
- Restricting storage account network access after pipeline IP/rules are finalized.
