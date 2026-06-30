# Camada de plataforma — AKS + ArgoCD

Esta pasta provisiona o cluster compartilhado (AKS) que hospeda o ArgoCD e as aplicações de todos os produtos.

## 1. Provisionar o AKS (Terraform)

```powershell
cd platform/terraform
terraform init
terraform apply -var="subscription_id=<subscription-id>"
```

> Para a POC, o estado é local. Em produção, use um backend remoto como na camada de state do `infra/`.

## 2. Obter credenciais do cluster

```powershell
az aks get-credentials --resource-group rg-platform-aks-poc --name aks-multiproduct-poc
```

## 3. Instalar o ArgoCD

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-applicationset-controller -n argocd
```

## 4. Aplicar o ApplicationSet

```powershell
kubectl apply -f ../../apps/appset/applicationset.yaml
```

O ArgoCD passa a criar automaticamente um `Application` por pasta em `apps/products/*`.

## 5. Verificar

```powershell
kubectl get applications -n argocd
kubectl get pods -n produto-a
kubectl get pods -n produto-b
```

## Limpeza

```powershell
cd platform/terraform
terraform destroy -var="subscription_id=<subscription-id>"
```
