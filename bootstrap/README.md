# Bootstrap Azure + GitHub OIDC

O script `bootstrap-state.ps1` prepara o Azure para que o workflow do GitHub Actions consiga executar Terraform sem armazenar senha ou client secret do Azure no GitHub.

Ele cria ou reutiliza:

- uma app registration no Microsoft Entra ID;
- um service principal para essa aplicação;
- uma federated credential de GitHub Actions na aplicação;
- um grupo de recursos, storage account e container para o state remoto do Terraform;
- permissões RBAC para o service principal;
- opcionalmente, variables (variáveis) e secrets (segredos) no repositório GitHub via `gh`.

## Por que isso é necessário

O workflow faz deploy no Azure usando OIDC:

1. O GitHub solicita um token OIDC de curta duração para a execução do workflow.
2. O Azure valida esse token contra a federated credential criada por este script.
3. A action `azure/login@v2` troca esse token por um access token do Azure.
4. O Terraform usa a mesma identidade para ler/gravar state e fazer deploy dos recursos.

Nenhum client secret do Azure é criado ou armazenado.

## Pré-requisitos

- Azure CLI autenticada no tenant alvo:

  ```powershell
  az login --tenant '<tenant-id>'
  ```

- Permissão para criar app registrations/service principals no Entra ID.
- Permissão para criar recursos Azure e role assignments na subscription alvo.
- Opcional: GitHub CLI autenticada com acesso ao repositório alvo, caso use `-ConfigureGitHub`.

## Configuração recomendada em um comando

Execute depois que o código já estiver publicado em um repositório GitHub. Substitua owner/repo pela organização/usuário e pelo nome real do repositório.

```powershell
.\bootstrap\bootstrap-state.ps1 `
  -TenantId '<tenant-id>' `
  -SubscriptionId '<subscription-id>' `
  -GitHubOwner '<github-owner-ou-org>' `
  -GitHubRepo '<nome-do-repositorio>' `
  -GitHubBranch 'main' `
  -ConfigureGitHub
```

Isso cria a identidade Azure e a federated credential para:

```text
repo:<github-owner-ou-org>/<nome-do-repositorio>:ref:refs/heads/main
```

E configura estes valores no GitHub:

| Tipo | Nome |
| --- | --- |
| Secret | `AZURE_CLIENT_ID` |
| Secret | `AZURE_TENANT_ID` |
| Secret | `AZURE_SUBSCRIPTION_ID` |
| Variable | `TF_STATE_RESOURCE_GROUP` |
| Variable | `TF_STATE_STORAGE_ACCOUNT` |
| Variable | `TF_STATE_CONTAINER` |

## Configuração apenas no Azure

Se você não quiser que o script chame a GitHub CLI, omita `-ConfigureGitHub`:

```powershell
.\bootstrap\bootstrap-state.ps1 `
  -TenantId '<tenant-id>' `
  -SubscriptionId '<subscription-id>' `
  -GitHubOwner '<github-owner-ou-org>' `
  -GitHubRepo '<nome-do-repositorio>' `
  -GitHubBranch 'main'
```

O script imprimirá os comandos `gh secret set` e `gh variable set` para execução manual.

## Apenas backend de state / uso avançado

O Terraform não consegue usar um backend Azure Storage até que o storage account e o container já existam. Execute `bootstrap-state.ps1` uma vez antes do primeiro deployment pelo GitHub Actions.

```powershell
.\bootstrap\bootstrap-state.ps1 `
  -TenantId '<tenant-id>' `
  -SubscriptionId '<subscription-id>' `
  -Location 'brazilsouth'
```

Se `-GitHubOwner` e `-GitHubRepo` forem omitidos, o script ainda cria a app no Entra ID, o service principal e o backend de state, mas não cria a federated credential. Nesse caso, crie a federated credential depois ou execute novamente o script com os parâmetros do GitHub.

## Parâmetros

| Parâmetro | Padrão | Finalidade |
| --- | --- | --- |
| `TenantId` | obrigatório | Tenant Entra usado pelo Azure Login OIDC. |
| `SubscriptionId` | obrigatório | Subscription Azure onde state e recursos dos produtos são implantados. |
| `Location` | `brazilsouth` | Região do grupo de recursos/storage account do state do Terraform. |
| `ResourceGroupName` | `rg-tfstate-multiproduct-poc` | Grupo de recursos do state remoto. |
| `StorageAccountName` | gerado | Nome fixo opcional do storage account de state. Deve ser globalmente único. |
| `ContainerName` | `tfstate` | Blob container para o state do Terraform. |
| `IdentityName` | `app-gha-multiproduct-terraform-poc` | Display name da aplicação no Entra ID. |
| `GitHubOwner` | nenhum | Owner/org do GitHub usado no subject da federated credential. |
| `GitHubRepo` | nenhum | Nome do repositório GitHub usado no subject da federated credential. |
| `GitHubBranch` | `main` | Branch autorizada a solicitar tokens Azure. |
| `ConfigureGitHub` | false | Também grava secrets (segredos) e variables (variáveis) no GitHub usando `gh`. |

## RBAC criado

Para a POC, o service principal recebe:

- `Contributor` na subscription alvo, para que o Terraform possa criar grupos de recursos e recursos por produto.
- `Storage Blob Data Contributor` no storage account de state, para que o Terraform possa ler/gravar state remoto usando autenticação Azure AD.

Para produção, reduza o escopo e considere identidades separadas para plan/apply.

## Configuração manual do GitHub

Se `-ConfigureGitHub` não for usado, configure manualmente os valores impressos pelo script:

```powershell
gh secret set AZURE_CLIENT_ID --body '<client-id>'
gh secret set AZURE_TENANT_ID --body '<tenant-id>'
gh secret set AZURE_SUBSCRIPTION_ID --body '<subscription-id>'
gh variable set TF_STATE_RESOURCE_GROUP --body '<state-rg>'
gh variable set TF_STATE_STORAGE_ACCOUNT --body '<state-storage-account>'
gh variable set TF_STATE_CONTAINER --body 'tfstate'
```
