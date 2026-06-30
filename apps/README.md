# Camada de aplicações — GitOps com ArgoCD ApplicationSet

Esta pasta resolve a dor levantada pelo CoE de Nuvem: **ajustes manuais na configuração do ArgoCD a cada produto**.

A camada de infraestrutura (Terraform + GitHub Actions) entrega os recursos Azure por produto. Esta camada entrega as **aplicações no Kubernetes**, também por produto, sem duplicar manifesto e sem editar o ArgoCD a cada novo produto.

## O problema

No uso comum do ArgoCD, cada produto exige um recurso `Application` próprio, criado e ajustado manualmente. Com muitos produtos, isso vira trabalho repetitivo e fonte de erro — exatamente a dor relatada.

## A solução: ApplicationSet com git directory generator

O `apps/appset/applicationset.yaml` usa o **git directory generator**, que varre `apps/products/*` e gera **um `Application` por pasta de produto**, automaticamente.

```text
apps/
|-- charts/
|   `-- product-app/        # chart Helm único e reutilizável
|-- products/
|   |-- produto-a/
|   |   `-- values.yaml      # só o que muda no Produto A
|   `-- produto-b/
|       `-- values.yaml      # só o que muda no Produto B
`-- appset/
    `-- applicationset.yaml  # gera 1 Application por pasta em products/
```

O mesmo princípio da matrix do GitHub Actions, agora no GitOps: **o que muda por produto é configuração (`values.yaml`), não código**.

## Como adicionar um novo produto (zero ajuste no ArgoCD)

1. Criar a pasta `apps/products/produto-c/`.
2. Criar `apps/products/produto-c/values.yaml`:

   ```yaml
   product: produto-c
   replicaCount: 3
   message: "Produto C - deploy isolado via ArgoCD ApplicationSet"
   ```

3. Commit e push para `main`.

O ArgoCD detecta a nova pasta e cria o `Application` `produto-c` sozinho, implantando no namespace `produto-c`. **Não é necessário editar nada no ArgoCD.**

## Escala por produto

O campo `replicaCount` em cada `values.yaml` demonstra escala independente por produto (por exemplo, muitas réplicas de um produto e poucas de outro), sem alterar o chart.

## Como aplicar

Veja [../platform/README.md](../platform/README.md) para provisionar o AKS, instalar o ArgoCD e aplicar o `ApplicationSet`.
