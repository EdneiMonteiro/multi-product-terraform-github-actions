# Guia da POC - Multi Deploy Terraform

## Resumo executivo

Esta POC demonstra como usar **um único repositório** para fazer **múltiplos deployments independentes no Azure**, um para cada produto, sem duplicar código Terraform.

O padrão é simples:

- o código de infraestrutura fica uma vez em `infra/`;
- cada produto tem apenas um arquivo de configuração em `config/`;
- o GitHub Actions executa uma matriz de produtos;
- cada produto usa um **state Terraform separado**;
- cada produto cria recursos em um **grupo de recursos separado**.

Resultado: o time consegue escalar de 2 para N produtos adicionando configuração, não copiando projeto.

## A dor que a POC resolve

O cenário-alvo é equivalente a:

> "Tenho um mesmo sistema, mas preciso subir infra independente por produto. Cada produto pode ter banco, storage, filas, DNS e escala próprios. Não quero copiar o repositório nem manter pipelines duplicadas."

Esta POC responde com um modelo de **código único + configuração por produto + execução independente**.

```mermaid
flowchart LR
    subgraph Antes["Antes: tendência comum"]
        A1["Repo Produto A"] --> A2["Pipeline A"] --> A3["Infra Produto A"]
        B1["Repo Produto B"] --> B2["Pipeline B"] --> B3["Infra Produto B"]
        C1["Repo Produto C"] --> C2["Pipeline C"] --> C3["Infra Produto C"]
    end

    subgraph Depois["Depois: proposta da POC"]
        R["Um único repo"] --> W["Um workflow com matrix"]
        W --> PA["Deploy Produto A"]
        W --> PB["Deploy Produto B"]
        W --> PC["Deploy Produto C"]
    end
```

## Visão geral da arquitetura

```mermaid
flowchart TB
    Dev["Dev faz push ou executa workflow manual"] --> GH["GitHub Actions"]

    GH --> Matrix{"Matrix de produtos"}
    Matrix --> JobA["Job produto-a"]
    Matrix --> JobB["Job produto-b"]

    GH --> OIDC["OIDC: token temporário"]
    OIDC --> Entra["Microsoft Entra ID\nApp Registration + Federated Credential"]
    Entra --> Azure["Azure Subscription"]

    JobA --> InitA["terraform init\nstate: products/produto-a/terraform.tfstate"]
    JobB --> InitB["terraform init\nstate: products/produto-b/terraform.tfstate"]

    InitA --> RG_A["rg-produto-a-terraform-poc"]
    InitB --> RG_B["rg-produto-b-terraform-poc"]

    Azure --> State["Storage remoto de state\nrg-tfstate-multiproduct-poc / tfstate"]
    InitA --> State
    InitB --> State
```

## Como o deploy acontece

```mermaid
sequenceDiagram
    participant Dev as Desenvolvedor
    participant GH as GitHub Actions
    participant Entra as Microsoft Entra ID
    participant TF as Terraform
    participant Azure as Azure
    participant State as Azure Storage State

    Dev->>GH: Push na main ou workflow_dispatch
    GH->>GH: Expande matrix: produto-a, produto-b
    GH->>Entra: Solicita token OIDC
    Entra-->>GH: Retorna token Azure de curta duração
    GH->>TF: terraform init com backend-config do produto
    TF->>State: Lê/grava state separado por produto
    GH->>TF: terraform plan com config/<produto>.tfvars
    GH->>TF: terraform apply
    TF->>Azure: Cria/atualiza RG, storage, container, fila
    Azure-->>GH: Deploy concluído
```

## Isolamento por produto

Mesmo com um único código Terraform, cada produto tem fronteiras próprias:

```mermaid
flowchart TB
    Code["infra/\nCódigo Terraform único"] --> AConfig["config/produto-a.tfvars"]
    Code --> BConfig["config/produto-b.tfvars"]

    AConfig --> AState["State A\nproducts/produto-a/terraform.tfstate"]
    BConfig --> BState["State B\nproducts/produto-b/terraform.tfstate"]

    AState --> ARG["Resource Group A\nrg-produto-a-terraform-poc"]
    BState --> BRG["Resource Group B\nrg-produto-b-terraform-poc"]

    ARG --> AResources["Storage / Container / Queue\nProduto A"]
    BRG --> BResources["Storage / Container / Queue\nProduto B"]
```

| Item | Produto A | Produto B |
| --- | --- | --- |
| Configuração | `config/produto-a.tfvars` | `config/produto-b.tfvars` |
| State | `products/produto-a/terraform.tfstate` | `products/produto-b/terraform.tfstate` |
| Grupo de recursos | `rg-produto-a-terraform-poc` | `rg-produto-b-terraform-poc` |
| Execução | Job matrix `produto-a` | Job matrix `produto-b` |

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
|       |-- 01-visao-geral.excalidraw
|       |-- 02-fluxo-deploy.excalidraw
|       `-- 03-isolamento-produtos.excalidraw
`-- infra/
    |-- backend.tf
    |-- main.tf
    |-- outputs.tf
    |-- providers.tf
    |-- variables.tf
    `-- versions.tf
```

## O que cada pasta faz

| Pasta/arquivo | Função |
| --- | --- |
| `.github/workflows/deploy.yml` | Pipeline GitHub Actions com matrix por produto. |
| `bootstrap/bootstrap-state.ps1` | Prepara Azure + GitHub OIDC + state remoto do Terraform. |
| `config/*.tfvars` | Define o que muda por produto. |
| `infra/*.tf` | Código Terraform reutilizável. |
| `docs/diagrams/*.excalidraw` | Diagramas editáveis para apresentação/arquitetura. |

## Segurança: por que OIDC

O workflow não usa senha ou client secret Azure. Ele usa OIDC:

```mermaid
flowchart LR
    GH["GitHub Actions\nid-token: write"] --> Token["OIDC token\ncurta duração"]
    Token --> Entra["Entra ID valida\nowner/repo/branch"]
    Entra --> Access["Azure access token"]
    Access --> TF["Terraform deploy"]
```

O Entra ID só aceita tokens com o subject configurado:

```text
repo:EdneiMonteiro/multi-product-terraform-github-actions:ref:refs/heads/main
```

Ou seja, apenas esse repositório e branch conseguem obter token para deploy.

## Como adicionar um novo produto

1. Criar um novo arquivo:

   ```text
   config/produto-c.tfvars
   ```

2. Preencher os valores específicos:

   ```hcl
   product             = "produto-c"
   environment         = "poc"
   location            = "brazilsouth"
   resource_group_name = "rg-produto-c-terraform-poc"
   ```

3. Adicionar uma entrada na matrix:

   ```yaml
   - product: produto-c
     tfvars: config/produto-c.tfvars
     state_key: products/produto-c/terraform.tfstate
   ```

4. Fazer push para `main` ou executar o workflow manualmente.

Não é necessário copiar a pasta `infra/` nem criar uma pipeline nova.

## O que foi implantado nesta POC

| Produto | Grupo de recursos | Storage account |
| --- | --- | --- |
| produto-a | `rg-produto-a-terraform-poc` | gerado pelo Terraform |
| produto-b | `rg-produto-b-terraform-poc` | gerado pelo Terraform |

States remotos confirmados:

```text
products/produto-a/terraform.tfstate
products/produto-b/terraform.tfstate
```

Workflow validado:

```text
Multi Deploy Terraform
status: sucesso
trigger: workflow_dispatch
```

## Ciclo operacional

```mermaid
flowchart LR
    Change["Alterar infra ou config"] --> PR["Abrir PR"]
    PR --> Review["Revisar mudança"]
    Review --> Main["Merge na main"]
    Main --> Deploy["GitHub Actions matrix"]
    Deploy --> Azure["Azure atualizado por produto"]
```

Para produção, recomenda-se evoluir para:

- separar `plan` e `apply`;
- exigir aprovação manual para `apply`;
- usar GitHub Environments;
- separar identidade de leitura/plan da identidade de escrita/apply;
- incluir policy-as-code e validações adicionais.

## Mensagem principal

Esta abordagem permite manter **um único repositório governado**, com **infraestrutura isolada por produto**, **state independente**, **deploy automatizado no Azure** e **baixo esforço para adicionar novos produtos**.
