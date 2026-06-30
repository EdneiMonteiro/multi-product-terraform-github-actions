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

A POC tem duas camadas, ambas seguindo o mesmo princípio (configuração por produto, não código duplicado):

- **Camada de infraestrutura**: Terraform + GitHub Actions (matrix) → recursos Azure por produto.
- **Camada de aplicações**: ArgoCD ApplicationSet (GitOps) → aplicações no Kubernetes por produto, sem ajuste manual no ArgoCD a cada produto.

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
    Dev["Dev executa o workflow manual (workflow_dispatch)"] --> GH["GitHub Actions"]

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

    Dev->>GH: Executa o workflow manual (workflow_dispatch)
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

## Escopo desta POC e extensões

A POC demonstra concretamente o **padrão**, com recursos simples e baratos por produto:

- grupo de recursos;
- storage account;
- container de blob;
- fila (queue).

A visão completa mencionada no cenário-alvo (banco de dados, DNS e escala própria por produto) **usa exatamente o mesmo padrão** — basta acrescentar recursos no código único em `infra/`, parametrizados por `tfvars`. Esses itens entram como extensão:

| Necessidade | Como estender (mesmo padrão, sem duplicar código) |
| --- | --- |
| Banco de dados por produto | Adicionar um recurso de banco no `infra/` (ex.: `azurerm_postgresql_flexible_server`), parametrizado por `tfvars`. |
| Filas de movimento | Já demonstrado via `azurerm_storage_queue`; pode evoluir para Service Bus por produto. |
| DNS por produto | Adicionar zona/registro DNS no `infra/` (ex.: `azurerm_dns_zone` ou DNS privado) para roteamento por produto. |
| Escala de execução (ex.: muitas réplicas de um produto, poucas de outro) | **Demonstrado** na camada de aplicações: o campo `replicaCount` no `values.yaml` de cada produto controla a escala independente, sem alterar o chart. Veja a seção da camada ArgoCD. |

Ou seja: o que muda entre produtos é **configuração**, não código.

## Camada de aplicações: ArgoCD ApplicationSet (GitOps)

Esta camada resolve a dor relatada pelo CoE de Nuvem: **ter que ajustar a configuração do ArgoCD manualmente a cada produto**.

### O problema

No uso comum do ArgoCD, cada produto exige um recurso `Application` próprio, criado e ajustado à mão. Com muitos produtos, isso vira trabalho repetitivo e fonte de erro.

### A solução

O `apps/appset/applicationset.yaml` usa o **git directory generator**: ele varre `apps/products/*` e gera **um `Application` por pasta de produto**, automaticamente. É o mesmo princípio da matrix do GitHub Actions, agora no GitOps.

```mermaid
flowchart TB
    subgraph Repo["Repositório único (Git)"]
        Chart["apps/charts/product-app\nchart Helm único"]
        PA["apps/products/produto-a/values.yaml"]
        PB["apps/products/produto-b/values.yaml"]
        PC["apps/products/produto-c/values.yaml"]
        AppSet["apps/appset/applicationset.yaml\ngit directory generator"]
    end

    AppSet -->|varre products/*| Gen{ApplicationSet}
    Gen --> AppA["Application produto-a"]
    Gen --> AppB["Application produto-b"]
    Gen --> AppC["Application produto-c"]

    AppA --> NSA["Namespace produto-a\n2 réplicas"]
    AppB --> NSB["Namespace produto-b\n1 réplica"]
    AppC --> NSC["Namespace produto-c\n3 réplicas"]

    Chart -.usa.-> AppA
    Chart -.usa.-> AppB
    Chart -.usa.-> AppC
```

### Adicionar um produto = zero ajuste no ArgoCD

1. Criar a pasta `apps/products/produto-c/` com um `values.yaml`.
2. Commit e push para `main`.
3. O ArgoCD detecta a nova pasta e cria o `Application` `produto-c` sozinho.

Nada é editado no ArgoCD. A escala (`replicaCount`) é definida no `values.yaml` de cada produto.

### Resultado validado nesta POC

Executado em um cluster AKS real (`aks-multiproduct-poc`) com ArgoCD instalado:

| Produto | Forma de inclusão | Réplicas | Estado |
| --- | --- | --- | --- |
| produto-a | pasta inicial | 2 | Synced / Healthy |
| produto-b | pasta inicial | 1 | Synced / Healthy |
| produto-c | adicionado só com push da pasta | 3 | Synced / Healthy |

O `produto-c` foi criado automaticamente pelo ApplicationSet após o push, **sem nenhuma alteração na configuração do ArgoCD** — exatamente o ponto de dor que o CoE de Nuvem levantou.

Detalhes de operação em [../apps/README.md](../apps/README.md) e [../platform/README.md](../platform/README.md).

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

Camadas adicionais de GitOps/Kubernetes:

```text
repo/
|-- apps/                          # camada de aplicações (ArgoCD)
|   |-- charts/product-app/        # chart Helm único e reutilizável
|   |-- products/                  # 1 pasta por produto (só values.yaml)
|   |   |-- produto-a/values.yaml
|   |   |-- produto-b/values.yaml
|   |   `-- produto-c/values.yaml
|   `-- appset/applicationset.yaml # git directory generator
`-- platform/                      # cluster compartilhado
    |-- README.md
    `-- terraform/                 # AKS via Terraform
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

4. Executar o workflow manualmente (`workflow_dispatch`), escolhendo `plan` ou `apply`.

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
    Main --> Deploy["Disparar workflow manual (plan/apply)"]
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
