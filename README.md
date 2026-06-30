# Deploy Terraform multi-produto com GitHub Actions

[![ORCID](https://img.shields.io/badge/ORCID-0009--0006--0765--4201-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0009-0006-0765-4201)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Azure](https://img.shields.io/badge/Cloud-Azure-0078D4?logo=microsoftazure&logoColor=white)](#)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-844FBA?logo=terraform&logoColor=white)](#)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?logo=githubactions&logoColor=white)](#)
[![OIDC](https://img.shields.io/badge/Auth-OIDC-107C10)](#)
[![Last commit](https://img.shields.io/github/last-commit/EdneiMonteiro/multi-product-terraform-github-actions)](https://github.com/EdneiMonteiro/multi-product-terraform-github-actions/commits)

Esta POC demonstra como um único repositório pode implantar infraestrutura Azure isolada para múltiplos produtos, sem duplicar código Terraform.

> ⚠️ Este repositório é uma **demo / prova de conceito**. Antes de usar em produção, revise segurança, permissões, custos, governança, observabilidade e conformidade. Veja [DISCLAIMER.md](./DISCLAIMER.md) e [SUPPORT.md](./SUPPORT.md).

Para a explicação completa da POC, com diagramas, consulte [`docs/GUIA_POC.md`](docs/GUIA_POC.md).

O workflow usa uma matrix do GitHub Actions para executar o mesmo código Terraform para cada produto. Cada produto tem:

- seu próprio arquivo `tfvars`;
- seu próprio grupo de recursos no Azure;
- sua própria chave de state remoto do Terraform;
- o mesmo código Terraform reutilizável em `infra/`.

## Configuração Azure esperada

- Tenant: informe via parâmetro `-TenantId` no bootstrap e secret `AZURE_TENANT_ID` no GitHub.
- Subscription: informe via parâmetro `-SubscriptionId` no bootstrap e secret `AZURE_SUBSCRIPTION_ID` no GitHub.
- Região padrão: `brazilsouth`

## Índice

- [Estrutura do repositório](#estrutura-do-repositório)
- [Bootstrap Azure e GitHub OIDC](#bootstrap-azure-e-github-oidc)
- [Secrets do GitHub](#secrets-do-github)
- [Validação local](#validação-local)
- [Como isso responde à necessidade de negócio](#como-isso-responde-à-necessidade-de-negócio)
- [Arquivos padrão do repositório](#arquivos-padrão-do-repositório)
- [Suporte e aviso legal](#suporte-e-aviso-legal)

## Estrutura do repositório

```text
repo/
|-- .github/
|   `-- workflows/
|       `-- deploy.yml
|-- bootstrap/
|   |-- README.md
|   `-- bootstrap-state.ps1
|-- config/
|   |-- produto-a.tfvars
|   `-- produto-b.tfvars
|-- docs/
|   |-- GUIA_POC.md
|   `-- diagrams/
|-- CITATION.cff
|-- DISCLAIMER.md
|-- LICENSE
|-- README.md
|-- SUPPORT.md
`-- infra/
    |-- backend.tf
    |-- main.tf
    |-- outputs.tf
    |-- providers.tf
    |-- variables.tf
    `-- versions.tf
```

## Bootstrap Azure e GitHub OIDC

Execute o bootstrap uma vez para criar a identidade Azure, a credencial federada do GitHub, as permissões RBAC e o backend de state do Terraform no Azure Storage:

```powershell
.\bootstrap\bootstrap-state.ps1 `
  -TenantId '<tenant-id>' `
  -SubscriptionId '<subscription-id>' `
  -GitHubOwner '<github-owner-ou-org>' `
  -GitHubRepo '<nome-do-repositorio>' `
  -GitHubBranch 'main' `
  -ConfigureGitHub
```

Se `-ConfigureGitHub` for omitido, o script apenas imprime os comandos `gh` para configurar manualmente secrets (segredos) e variables (variáveis) no GitHub.

O workflow precisa destas variáveis do GitHub:

- `TF_STATE_RESOURCE_GROUP`
- `TF_STATE_STORAGE_ACCOUNT`
- `TF_STATE_CONTAINER`

## Secrets do GitHub

Configure estes secrets (segredos) no repositório ou em um environment do GitHub:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

A identidade por trás de `AZURE_CLIENT_ID` precisa ter uma federated credential confiando neste repositório GitHub e permissões RBAC suficientes para:

- fazer deploy de recursos na subscription configurada;
- ler/gravar blobs no storage account usado pelo state remoto do Terraform.

Para a POC, `Contributor` na subscription e `Storage Blob Data Contributor` no storage account de state são suficientes. Para produção, reduza o escopo dessas permissões e considere identidades separadas para plan/apply.

## Validação local

A partir da raiz do repositório:

```powershell
terraform fmt -check -recursive
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
```

## Como isso responde à necessidade de negócio

Adicionar um novo produto não exige copiar Terraform. Basta criar um novo arquivo `config/<produto>.tfvars` e adicionar uma entrada na matrix de `.github/workflows/deploy.yml`. A pipeline produzirá um deployment e um state separado para esse produto.

## Arquivos padrão do repositório

| Arquivo | Descrição |
| --- | --- |
| [LICENSE](./LICENSE) | Licença MIT do projeto. |
| [CITATION.cff](./CITATION.cff) | Metadados de citação do repositório. |
| [DISCLAIMER.md](./DISCLAIMER.md) | Aviso legal e limites de uso da POC. |
| [SUPPORT.md](./SUPPORT.md) | Como pedir ajuda e limites de suporte. |
| [docs/GUIA_POC.md](./docs/GUIA_POC.md) | Guia em pt-BR para explicar a POC, com diagramas. |
| [bootstrap/README.md](./bootstrap/README.md) | Detalhes do bootstrap Azure + GitHub OIDC. |

## Suporte e aviso legal

- Sem SLA nem suporte oficial. Veja [SUPPORT.md](./SUPPORT.md).
- Uso sujeito ao aviso legal em [DISCLAIMER.md](./DISCLAIMER.md).
- Esta POC não substitui revisão de arquitetura, segurança, custos e governança antes de qualquer uso produtivo.
