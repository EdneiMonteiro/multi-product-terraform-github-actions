[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    [string]$Location = 'brazilsouth',
    [string]$ResourceGroupName = 'rg-tfstate-multiproduct-poc',
    [string]$StorageAccountName,
    [string]$ContainerName = 'tfstate',
    [string]$IdentityName = 'app-gha-multiproduct-terraform-poc',
    [string]$GitHubOwner,
    [string]$GitHubRepo,
    [string]$GitHubBranch = 'main',
    [switch]$ConfigureGitHub
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: az $($Arguments -join ' ')"
    }

    return $output
}

function Invoke-GhCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & gh @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI failed: gh $($Arguments -join ' ')"
    }

    return $output
}

function New-StorageAccountName {
    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'.ToCharArray()
    $suffix = -join (1..8 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return "tfst$suffix"
}

function Ensure-RoleAssignment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssigneeObjectId,
        [Parameter(Mandatory = $true)]
        [string]$Role,
        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    $assignmentsJson = Invoke-AzCli @(
        'role', 'assignment', 'list',
        '--assignee', $AssigneeObjectId,
        '--role', $Role,
        '--scope', $Scope,
        '-o', 'json'
    )
    $assignments = $assignmentsJson | ConvertFrom-Json

    if ($assignments.Count -eq 0) {
        Invoke-AzCli @(
            'role', 'assignment', 'create',
            '--assignee-object-id', $AssigneeObjectId,
            '--assignee-principal-type', 'ServicePrincipal',
            '--role', $Role,
            '--scope', $Scope,
            '--only-show-errors'
        ) | Out-Null
    }
}

function Get-ServicePrincipalObjectId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientId
    )

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $objectId = & az ad sp show --id $ClientId --query id -o tsv --only-show-errors 2>$null

        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($objectId)) {
            return $objectId
        }

        Start-Sleep -Seconds 5
    }

    throw "Service principal for client id '$ClientId' was not available after waiting."
}

function Ensure-GitHubFederatedIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [string]$Branch
    )

    $credentialName = "github-$Owner-$Repo-$Branch" -replace '[^a-zA-Z0-9_-]', '-'
    if ($credentialName.Length -gt 120) {
        $credentialName = $credentialName.Substring(0, 120)
    }

    $subject = "repo:$Owner/$($Repo):ref:refs/heads/$Branch"
    $credentialsJson = Invoke-AzCli @(
        'ad', 'app', 'federated-credential', 'list',
        '--id', $ClientId,
        '-o', 'json',
        '--only-show-errors'
    )
    $credentials = $credentialsJson | ConvertFrom-Json
    $existing = @($credentials | Where-Object { $_.name -eq $credentialName }).Count

    if ($existing -eq 0) {
        $credential = @{
            name        = $credentialName
            issuer      = 'https://token.actions.githubusercontent.com'
            subject     = $subject
            description = "GitHub Actions OIDC for $Owner/$Repo on branch $Branch"
            audiences   = @('api://AzureADTokenExchange')
        }

        $credentialPath = Join-Path ([System.IO.Path]::GetTempPath()) "$credentialName.json"
        $credential | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $credentialPath -Encoding utf8

        try {
            Invoke-AzCli @(
                'ad', 'app', 'federated-credential', 'create',
                '--id', $ClientId,
                '--parameters', $credentialPath,
                '--only-show-errors'
            ) | Out-Null
        }
        finally {
            Remove-Item -LiteralPath $credentialPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $subject
}

function Ensure-GitHubVariables {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $true)]
        [string]$StateResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$StateStorageAccount,
        [Parameter(Mandatory = $true)]
        [string]$StateContainer
    )

    $repoFullName = "$Owner/$Repo"

    Invoke-GhCli @('variable', 'set', 'TF_STATE_RESOURCE_GROUP', '--repo', $repoFullName, '--body', $StateResourceGroup) | Out-Null
    Invoke-GhCli @('variable', 'set', 'TF_STATE_STORAGE_ACCOUNT', '--repo', $repoFullName, '--body', $StateStorageAccount) | Out-Null
    Invoke-GhCli @('variable', 'set', 'TF_STATE_CONTAINER', '--repo', $repoFullName, '--body', $StateContainer) | Out-Null

    Invoke-GhCli @('secret', 'set', 'AZURE_CLIENT_ID', '--repo', $repoFullName, '--body', $ClientId) | Out-Null
    Invoke-GhCli @('secret', 'set', 'AZURE_TENANT_ID', '--repo', $repoFullName, '--body', $TenantId) | Out-Null
    Invoke-GhCli @('secret', 'set', 'AZURE_SUBSCRIPTION_ID', '--repo', $repoFullName, '--body', $SubscriptionId) | Out-Null
}

Invoke-AzCli @('account', 'show', '--query', 'tenantId', '-o', 'tsv') | Out-Null
Invoke-AzCli @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

$account = Invoke-AzCli @('account', 'show', '--query', '{tenantId:tenantId, subscriptionId:id}', '-o', 'json') | ConvertFrom-Json
if ($account.tenantId -ne $TenantId) {
    throw "Current Azure tenant is '$($account.tenantId)', expected '$TenantId'. Run az login --tenant $TenantId and retry."
}
if ($account.subscriptionId -ne $SubscriptionId) {
    throw "Current Azure subscription is '$($account.subscriptionId)', expected '$SubscriptionId'."
}

$clientId = Invoke-AzCli @(
    'ad', 'app', 'list',
    '--display-name', $IdentityName,
    '--query', '[0].appId',
    '-o', 'tsv',
    '--only-show-errors'
)

if ([string]::IsNullOrWhiteSpace($clientId)) {
    $clientId = Invoke-AzCli @(
        'ad', 'app', 'create',
        '--display-name', $IdentityName,
        '--query', 'appId',
        '-o', 'tsv',
        '--only-show-errors'
    )
}

& az ad sp show --id $clientId --only-show-errors 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-AzCli @('ad', 'sp', 'create', '--id', $clientId, '--only-show-errors') | Out-Null
}

$principalObjectId = Get-ServicePrincipalObjectId -ClientId $clientId

$federatedSubject = $null
if (-not [string]::IsNullOrWhiteSpace($GitHubOwner) -and -not [string]::IsNullOrWhiteSpace($GitHubRepo)) {
    $federatedSubject = Ensure-GitHubFederatedIdentity -ClientId $clientId -Owner $GitHubOwner -Repo $GitHubRepo -Branch $GitHubBranch
}

Invoke-AzCli @(
    'group', 'create',
    '--name', $ResourceGroupName,
    '--location', $Location,
    '--tags',
    'purpose=terraform-state',
    'poc=multi-product-terraform-github-actions',
    '--only-show-errors'
) | Out-Null

if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
    $storageAccountsJson = Invoke-AzCli @(
        'storage', 'account', 'list',
        '--resource-group', $ResourceGroupName,
        '-o', 'json',
        '--only-show-errors'
    )
    $storageAccounts = $storageAccountsJson | ConvertFrom-Json
    $existingStorageAccount = @(
        $storageAccounts | Where-Object {
            $_.tags.purpose -eq 'terraform-state' -and $_.tags.poc -eq 'multi-product-terraform-github-actions'
        } | Select-Object -First 1
    )

    if ($existingStorageAccount.Count -eq 0) {
        $StorageAccountName = New-StorageAccountName
    }
    else {
        $StorageAccountName = $existingStorageAccount[0].name
    }
}

$StorageAccountName = $StorageAccountName.ToLowerInvariant()
if ($StorageAccountName -notmatch '^[a-z0-9]{3,24}$') {
    throw 'Storage account name must be 3-24 characters and contain only lowercase letters and numbers.'
}

$storageExists = $true
& az storage account show --resource-group $ResourceGroupName --name $StorageAccountName --only-show-errors 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    $storageExists = $false
}

if (-not $storageExists) {
    Invoke-AzCli @(
        'storage', 'account', 'create',
        '--resource-group', $ResourceGroupName,
        '--name', $StorageAccountName,
        '--location', $Location,
        '--sku', 'Standard_LRS',
        '--kind', 'StorageV2',
        '--min-tls-version', 'TLS1_2',
        '--allow-blob-public-access', 'false',
        '--https-only', 'true',
        '--tags',
        'purpose=terraform-state',
        'poc=multi-product-terraform-github-actions',
        '--only-show-errors'
    ) | Out-Null
}

Invoke-AzCli @(
    'storage', 'container', 'create',
    '--name', $ContainerName,
    '--account-name', $StorageAccountName,
    '--auth-mode', 'key',
    '--only-show-errors'
) | Out-Null

$storageAccountId = Invoke-AzCli @(
    'storage', 'account', 'show',
    '--resource-group', $ResourceGroupName,
    '--name', $StorageAccountName,
    '--query', 'id',
    '-o', 'tsv'
)

Ensure-RoleAssignment -AssigneeObjectId $principalObjectId -Role 'Contributor' -Scope "/subscriptions/$SubscriptionId"
Ensure-RoleAssignment -AssigneeObjectId $principalObjectId -Role 'Storage Blob Data Contributor' -Scope $storageAccountId

if ($ConfigureGitHub) {
    if ([string]::IsNullOrWhiteSpace($GitHubOwner) -or [string]::IsNullOrWhiteSpace($GitHubRepo)) {
        throw 'Use -GitHubOwner and -GitHubRepo when passing -ConfigureGitHub.'
    }

    Ensure-GitHubVariables `
        -Owner $GitHubOwner `
        -Repo $GitHubRepo `
        -ClientId $clientId `
        -TenantId $TenantId `
        -SubscriptionId $SubscriptionId `
        -StateResourceGroup $ResourceGroupName `
        -StateStorageAccount $StorageAccountName `
        -StateContainer $ContainerName
}

Write-Host ''
Write-Host 'Azure and GitHub Actions bootstrap is ready.'
Write-Host ''
Write-Host "Client ID: $clientId"
Write-Host "Service principal object ID: $principalObjectId"
if ($federatedSubject) {
    Write-Host "Federated subject: $federatedSubject"
}
else {
    Write-Host 'Federated credential was not created because -GitHubOwner/-GitHubRepo were not provided.'
}
Write-Host ''
Write-Host 'State backend:'
Write-Host "Resource group: $ResourceGroupName"
Write-Host "Storage account: $StorageAccountName"
Write-Host "Container: $ContainerName"
Write-Host ''
Write-Host 'If -ConfigureGitHub was not used, configure GitHub with:'
Write-Host "gh variable set TF_STATE_RESOURCE_GROUP --body '$ResourceGroupName'"
Write-Host "gh variable set TF_STATE_STORAGE_ACCOUNT --body '$StorageAccountName'"
Write-Host "gh variable set TF_STATE_CONTAINER --body '$ContainerName'"
Write-Host "gh secret set AZURE_CLIENT_ID --body '$clientId'"
Write-Host "gh secret set AZURE_TENANT_ID --body '$TenantId'"
Write-Host "gh secret set AZURE_SUBSCRIPTION_ID --body '$SubscriptionId'"
