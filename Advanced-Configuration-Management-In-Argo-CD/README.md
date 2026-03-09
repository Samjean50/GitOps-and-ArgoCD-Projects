# Module 3: Advanced Configuration Management in ArgoCD

## Mini Project — GitOps Configuration Management

![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-orange)
![Kubernetes](https://img.shields.io/badge/Kubernetes-EKS-blue)
![Terraform](https://img.shields.io/badge/IaC-Terraform-purple)
![Helm](https://img.shields.io/badge/Helm-Chart-green)
![Kustomize](https://img.shields.io/badge/Kustomize-Overlays-yellow)

---

## Table of Contents

- [Module 3: Advanced Configuration Management in ArgoCD](#module-3-advanced-configuration-management-in-argocd)
  - [Mini Project — GitOps Configuration Management](#mini-project--gitops-configuration-management)
  - [Table of Contents](#table-of-contents)
  - [Project Overview](#project-overview)
  - [Architecture](#architecture)
  - [Prerequisites](#prerequisites)
  - [Infrastructure Provisioning with Terraform](#infrastructure-provisioning-with-terraform)
    - [Directory Structure](#directory-structure)
    - [provider.tf](#providertf)
    - [variables.tf](#variablestf)
    - [main.tf](#maintf)
    - [secrets\_manager.tf](#secrets_managertf)
    - [Apply Terraform](#apply-terraform)
  - [ArgoCD Installation](#argocd-installation)
  - [Lesson 3.1 — Helm \& Kustomize](#lesson-31--helm--kustomize)
    - [Part 1: Helm Chart](#part-1-helm-chart)
    - [Part 2: Kustomize Multi-Environment](#part-2-kustomize-multi-environment)
  - [Lesson 3.2 — Secrets Management](#lesson-32--secrets-management)
    - [Part 1: Basic Kubernetes Secret](#part-1-basic-kubernetes-secret)
    - [Part 2: AWS Secrets Manager with External Secrets Operator](#part-2-aws-secrets-manager-with-external-secrets-operator)
  - [Lesson 3.3 — Resource Management \& Sync Policies](#lesson-33--resource-management--sync-policies)
    - [Resource Ignore Differences](#resource-ignore-differences)
    - [Custom Lua Health Check](#custom-lua-health-check)
    - [Automated Sync with Self-Healing \& Pruning](#automated-sync-with-self-healing--pruning)
  - [Project Structure](#project-structure)
  - [Verification \& Testing](#verification--testing)
  - [Cleanup](#cleanup)
- [STEPS TAKEN](#steps-taken)

---

## Project Overview

This project demonstrates advanced configuration management in ArgoCD using:

- **Helm** for templated application packaging and deployment
- **Kustomize** for multi-environment (dev/prod) configuration overlays
- **Kubernetes Secrets** and **AWS Secrets Manager** via the External Secrets Operator for secure secrets management
- **Resource customizations** including ignore differences and custom Lua health checks
- **Automated sync policies** with self-healing and pruning

---

## Architecture

```
GitHub Repository
       │
       ▼
   ArgoCD (EKS)
       │
       ├── my-helm-app (default namespace)
       │       └── Helm Chart → nginx deployment (2 replicas)
       │
       ├── my-app-kustomize-dev (dev namespace)
       │       └── Kustomize overlay → nginx deployment (1 replica)
       │
       └── my-app-kustomize-prod (prod namespace)
               └── Kustomize overlay → nginx deployment (3 replicas)

AWS Services
       ├── EKS Cluster (us-east-1)
       ├── AWS Secrets Manager (my-app/password)
       └── IAM Role (external-secrets-irsa via IRSA)
```

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.5 | Infrastructure provisioning |
| AWS CLI | >= 2.0 | AWS resource management |
| kubectl | >= 1.29 | Kubernetes management |
| Helm | >= 3.0 | Chart deployment |
| ArgoCD CLI | >= 2.8 | ArgoCD management |
| Git | Any | Source control |

---

## Infrastructure Provisioning with Terraform

All AWS infrastructure is provisioned using Terraform, including the EKS cluster, VPC, AWS Secrets Manager secret, and IAM roles for External Secrets Operator (IRSA).

### Directory Structure

```
terraform/
├── provider.tf
├── variables.tf
├── main.tf
└── secrets_manager.tf
```

### provider.tf

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

### variables.tf

```hcl
variable "aws_region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "gitops-module3-cluster"
}

variable "cluster_version" {
  default = "1.29"
}
```

### main.tf

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    main = {
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      instance_types = ["t3.medium"]
    }
  }

  access_entries = {
    samjean = {
      principal_arn = "arn:aws:iam::YOUR_ACCOUNT_ID:user/samjean"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}
```

### secrets_manager.tf

```hcl
resource "aws_secretsmanager_secret" "app_secret" {
  name        = "my-app/password"
  description = "Application password for GitOps module3"
}

resource "aws_secretsmanager_secret_version" "app_secret_value" {
  secret_id     = aws_secretsmanager_secret.app_secret.id
  secret_string = jsonencode({ password = "mypassword" })
}

module "irsa_external_secrets" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "external-secrets-irsa"

  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = [aws_secretsmanager_secret.app_secret.arn]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets-sa"]
    }
  }
}
```

### Apply Terraform

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name gitops-module3-cluster --profile samjean

# Verify
kubectl get nodes
```

---

## ArgoCD Installation

```bash
# Create namespace and install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port-forward (keep running in a separate terminal)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login via CLI
argocd login localhost:8080 --username admin --insecure
```

---

## Lesson 3.1 — Helm & Kustomize

### Part 1: Helm Chart

The Helm chart is located in `my-app/` and deploys an nginx application.

**Structure:**

```
my-app/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── deployment.yaml
    └── service.yaml
```

**Deploy via ArgoCD:**

```bash
argocd app create my-helm-app \
  --repo https://github.com/Samjean50/Advanced-Configuration-Management-In-Argo-CD.git \
  --path my-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --helm-set replicaCount=2

argocd app sync my-helm-app
```

---

### Part 2: Kustomize Multi-Environment

The Kustomize setup in `my-app-kustomize/` supports dev and prod environments with different replica counts.

**Structure:**

```
my-app-kustomize/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── patch.yaml        # replicas: 1
    └── prod/
        ├── kustomization.yaml
        └── patch.yaml        # replicas: 3
```

**Deploy via ArgoCD:**

```bash
kubectl create namespace dev
kubectl create namespace prod

argocd app create my-app-kustomize-dev --repo https://github.com/Samjean50/Advanced-Configuration-Management-In-Argo-CD.git --path my-app-kustomize/overlays/dev --dest-server https://kubernetes.default.svc --dest-namespace dev

argocd app create my-app-kustomize-prod --repo https://github.com/Samjean50/Advanced-Configuration-Management-In-Argo-CD.git --path my-app-kustomize/overlays/prod --dest-server https://kubernetes.default.svc --dest-namespace prod

argocd app sync my-app-kustomize-dev
argocd app sync my-app-kustomize-prod
```

---

## Lesson 3.2 — Secrets Management

### Part 1: Basic Kubernetes Secret

```bash
# Create secret in dev namespace
kubectl create secret generic my-secret --from-literal=password=mypassword -n dev

# Verify
kubectl get secret my-secret -n dev -o yaml
```

The secret is referenced in `base/deployment.yaml` via `secretKeyRef`:

```yaml
env:
- name: MY_PASSWORD
  valueFrom:
    secretKeyRef:
      name: my-secret
      key: password
```

---

### Part 2: AWS Secrets Manager with External Secrets Operator

The Terraform configuration already provisions the AWS Secrets Manager secret and IRSA role. Install the External Secrets Operator and configure it to sync secrets from AWS.

**Install External Secrets Operator:**

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

cat > eso-values.yaml <<'EOF'
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::YOUR_ACCOUNT_ID:role/external-secrets-irsa
EOF

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version 0.9.11 \
  --values eso-values.yaml
```

**ClusterSecretStore:**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

**ExternalSecret:**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secret
  namespace: dev
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: my-secret
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: my-app/password
      property: password
```

---

## Lesson 3.3 — Resource Management & Sync Policies

### Resource Ignore Differences

Added to `argocd-cm` ConfigMap to tell ArgoCD to ignore annotation changes on Ingress resources:

```yaml
resource.ignoreDifferences: |
  - group: networking.k8s.io
    kind: Ingress
    jsonPointers:
    - /metadata/annotations
```

### Custom Lua Health Check

Added to `argocd-cm` ConfigMap to define a custom health check for `custom.io/MyResource`:

```yaml
resource.customizations: |
  custom.io/MyResource:
    health.lua: |
      hs = {}
      if obj.status ~= nil then
        if obj.status.condition == "Healthy" then
          hs.status = "Healthy"
          hs.message = obj.status.message
        else
          hs.status = "Degraded"
          hs.message = obj.status.message
        end
      end
      return hs
```

### Automated Sync with Self-Healing & Pruning

```bash
argocd app set my-app-kustomize-dev \
  --sync-policy automated \
  --auto-prune \
  --self-heal

argocd app set my-app-kustomize-prod \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

This enables:
- **Automated sync** — ArgoCD automatically applies changes from Git
- **Pruning** — resources removed from Git are deleted from the cluster
- **Self-healing** — any manual changes to the cluster are automatically reverted

---

## Project Structure

```
Advanced-Configuration-Management-In-Argo-CD/
├── terraform/
│   ├── provider.tf
│   ├── variables.tf
│   ├── main.tf
│   └── secrets_manager.tf
├── my-app/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       └── service.yaml
├── my-app-kustomize/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   └── patch.yaml
│       └── prod/
│           ├── kustomization.yaml
│           └── patch.yaml
├── secretstore.yaml
├── externalsecret.yaml
└── README.md
```

---

## Verification & Testing

```bash
# Cluster nodes
kubectl get nodes

# All ArgoCD apps
argocd app list

# Helm app
kubectl get all -n default | grep my-helm

# Kustomize environments
kubectl get pods -n dev
kubectl get pods -n prod

# Secret injection
kubectl exec -it $(kubectl get pod -n dev -l app=my-app-kustomize \
  -o jsonpath='{.items[0].metadata.name}') -n dev -- env | grep MY_PASSWORD

# External Secrets
kubectl get externalsecret -n dev

# Sync policies
argocd app get my-app-kustomize-dev | grep "Sync Policy"
argocd app get my-app-kustomize-prod | grep "Sync Policy"

# Self-heal test
kubectl delete pod -l app=my-app-kustomize -n dev
kubectl get pods -n dev -w
```

---

## Cleanup

```bash
# Delete ArgoCD apps
argocd app delete my-helm-app
argocd app delete my-app-kustomize-dev
argocd app delete my-app-kustomize-prod

# Destroy all AWS infrastructure
cd terraform
terraform destroy
```

# STEPS TAKEN

![steps](images/1.png)
![steps](images/2.png)
![steps](images/3.png)
![steps](images/4.png)
![steps](images/5.png)
![steps](images/6.png)
![steps](images/7.png)
![steps](images/8.png)
![steps](images/9.png)
![steps](images/10.png)
![steps](images/11.png)
![steps](images/12.png)
![steps](images/13.png)
![steps](images/14.png)
![steps](images/15.png)
![steps](images/16.png)
![steps](images/17.png)
![steps](images/18.png)
![steps](images/19.png)
![steps](images/20.png)
![steps](images/21.png)
![steps](images/22.png)
![steps](images/23.png)
![steps](images/24.png)
![steps](images/25.png)
![steps](images/26.png)
![steps](images/27.png)
![steps](images/28.png)
![steps](images/29.png)
![steps](images/30.png)
![steps](images/31.png)
![steps](images/32.png)
![steps](images/33.png)
![steps](images/34.png)
![steps](images/35.png)
![steps](images/36.0.png)
![steps](images/36.png)
![steps](images/37.png)
![steps](images/38.png)
![steps](images/39.png)
![steps](images/40.png)
![steps](images/41.png)
![steps](images/42.png)
![steps](images/43.png)
![steps](images/44.png)
![steps](images/45.png)
![steps](images/46.png)
![steps](images/47.png)
![steps](images/48.png)
![steps](images/49.png)
![steps](images/50.png)