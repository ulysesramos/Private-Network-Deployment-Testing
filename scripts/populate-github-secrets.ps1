[CmdletBinding()]
# Example usage:
# .\scripts\populate-github-secrets.ps1 -SpnJsonPath .\spn.json -VmAdminUsername "vmadmin" -VmAdminPassword (Read-Host -AsSecureString "PNDT_VM_ADMIN_PASSWORD") -SetSubscriptionVariable
#
# Or, if you want the script to auto-detect the repo from the local Git origin:
# .\scripts\populate-github-secrets.ps1 -SpnJsonPath .\spn.json -VmAdminUsername "vmadmin" -VmAdminPassword (Read-Host -AsSecureString "PNDT_VM_ADMIN_PASSWORD") -SetSubscriptionVariable

param(
  [Parameter(Mandatory = $false)]
  [string]$Repository,

  [Parameter(Mandatory = $false)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $false)]
  [string]$TenantId,

  [Parameter(Mandatory = $false)]
  [string]$ClientId,

  [Parameter(Mandatory = $false)]
  [string]$ClientSecret,

  [Parameter(Mandatory = $false)]
  [string]$SpnJsonPath,

  [Parameter(Mandatory = $false)]
  [string]$VmAdminUsername,

  [Parameter(Mandatory = $false)]
  [SecureString]$VmAdminPassword,

  [Parameter(Mandatory = $false)]
  [switch]$SetSubscriptionVariable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-PlainText {
  param([Parameter(Mandatory = $true)][SecureString]$SecureStringValue)

  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureStringValue)
  try {
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Set-GitHubSecret {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$RepositoryName
  )

  gh secret set $Name --repo $RepositoryName --body "$Value" | Out-Null
}

function Set-GitHubVariable {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$RepositoryName
  )

  gh variable set $Name --repo $RepositoryName --body "$Value" | Out-Null
}

function Resolve-GitHubRepository {
  $repoRoot = git rev-parse --show-toplevel 2>$null
  if (-not $repoRoot) {
    throw 'Repository was not provided and the current directory is not inside a Git repository.'
  }

  $originUrl = git -C $repoRoot remote get-url origin 2>$null
  if (-not $originUrl) {
    throw 'Repository was not provided and the Git remote ``origin`` could not be found.'
  }

  if ($originUrl -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(?:\.git)?$') {
    return "$($Matches.owner)/$($Matches.repo)"
  }

  throw "Unable to derive owner/repository from origin URL: $originUrl"
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw 'GitHub CLI (gh) is not installed. Install it first, then rerun this script.'
}

if (-not (gh auth status 2>$null)) {
  throw 'GitHub CLI is not authenticated. Run `gh auth login` first, then rerun this script.'
}

if (-not $Repository) {
  $Repository = Resolve-GitHubRepository
}

if (-not $ClientId -or -not $ClientSecret -or -not $TenantId -or -not $SubscriptionId) {
  if (-not $SpnJsonPath) {
    throw 'Provide either -SpnJsonPath or all of -ClientId, -ClientSecret, -TenantId, and -SubscriptionId.'
  }

  if (-not (Test-Path -LiteralPath $SpnJsonPath)) {
    throw "SPN JSON file not found: $SpnJsonPath"
  }

  $spnJson = Get-Content -LiteralPath $SpnJsonPath -Raw | ConvertFrom-Json
  $ClientId = $spnJson.clientId
  $ClientSecret = $spnJson.clientSecret
  $TenantId = $spnJson.tenantId
  $SubscriptionId = $spnJson.subscriptionId
}

if (-not $VmAdminUsername) {
  $VmAdminUsername = Read-Host 'PNDT_VM_ADMIN_USERNAME'
}

if (-not $VmAdminPassword) {
  $VmAdminPassword = Read-Host 'PNDT_VM_ADMIN_PASSWORD' -AsSecureString
}

$vmAdminPasswordPlain = ConvertTo-PlainText -SecureStringValue $VmAdminPassword

$spnPayload = @{
  clientId                       = $ClientId
  clientSecret                   = $ClientSecret
  subscriptionId                 = $SubscriptionId
  tenantId                       = $TenantId
  activeDirectoryEndpointUrl     = 'https://login.microsoftonline.us'
  resourceManagerEndpointUrl     = 'https://management.usgovcloudapi.net/'
  activeDirectoryGraphResourceId = 'https://graph.windows.net/'
  sqlManagementEndpointUrl       = 'https://management.core.usgovcloudapi.net:8443/'
  galleryEndpointUrl             = 'https://gallery.usgovcloudapi.net/'
  managementEndpointUrl          = 'https://management.core.usgovcloudapi.net/'
} | ConvertTo-Json -Compress

Set-GitHubSecret -Name 'AZURE_P_PNDT_SPN' -Value $spnPayload -RepositoryName $Repository
Set-GitHubSecret -Name 'AZURE_P_PNDT_SPN_CLIENT_ID' -Value $ClientId -RepositoryName $Repository
Set-GitHubSecret -Name 'AZURE_P_PNDT_SPN_CLIENT_SECRET' -Value $ClientSecret -RepositoryName $Repository
Set-GitHubSecret -Name 'AZURE_PNDT_TENANT_ID' -Value $TenantId -RepositoryName $Repository
Set-GitHubSecret -Name 'PNDT_VM_ADMIN_USERNAME' -Value $VmAdminUsername -RepositoryName $Repository
Set-GitHubSecret -Name 'PNDT_VM_ADMIN_PASSWORD' -Value $vmAdminPasswordPlain -RepositoryName $Repository

if ($SetSubscriptionVariable) {
  Set-GitHubVariable -Name 'AZURE_P_PNDT_SUB_ID' -Value $SubscriptionId -RepositoryName $Repository
}

Write-Host 'GitHub secrets updated successfully.' -ForegroundColor Green
if ($SetSubscriptionVariable) {
  Write-Host 'GitHub variable AZURE_P_PNDT_SUB_ID updated successfully.' -ForegroundColor Green
}
