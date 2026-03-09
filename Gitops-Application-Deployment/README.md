# GitOps Application Deployment with ArgoCD on AWS EKS

![ArgoCD](https://img.shields.io/badge/ArgoCD-v2.x-orange?style=flat-square&logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.29-blue?style=flat-square&logo=kubernetes)
![Terraform](https://img.shields.io/badge/Terraform-v1.0+-purple?style=flat-square&logo=terraform)
![AWS](https://img.shields.io/badge/AWS-EKS-yellow?style=flat-square&logo=amazonaws)
![nginx](https://img.shields.io/badge/App-nginx-green?style=flat-square&logo=nginx)

## Overview

This project demonstrates a production-grade **GitOps workflow** using **ArgoCD** on **AWS EKS**, provisioned with **Terraform**. It covers the full lifecycle of deploying and managing a Kubernetes application — from infrastructure provisioning to application syncing, health monitoring, and rollbacks — following GitOps principles where Git is the single source of truth.

This project was completed as part of the **Darey.io Xternship Program — Module 2: Application Deployment and Management in ArgoCD**.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Developer                             │
│                  git push → GitHub Repo                      │
└───────────────────────────┬─────────────────────────────────┘
                            │  Webhook / Poll
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                        ArgoCD                                │
│         Detects drift → Syncs desired state                  │
└───────────────────────────┬─────────────────────────────────┘
                            │  kubectl apply
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     AWS EKS Cluster                          │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐   │
│  │  Node Group │   │  Namespace  │   │  nginx Pods     │   │
│  │  t3.medium  │   │  default    │   │  (2-4 replicas) │   │
│  └─────────────┘   └─────────────┘   └─────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │          AWS Load Balancer (External Access)         │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
              ┌─────────────┴──────────────┐
              ▼                            ▼
┌─────────────────────┐      ┌─────────────────────────────┐
│   Terraform (IaC)   │      │        VPC & Networking      │
│   EKS Cluster       │      │   Public & Private Subnets   │
│   Node Groups       │      │   NAT Gateway, Route Tables  │
│   IAM Roles         │      │   us-east-1a/b/c             │
└─────────────────────┘      └─────────────────────────────┘
```

---

## Tech Stack

| Tool | Purpose |
|---|---|
| **Terraform** | Infrastructure as Code — provisions VPC, EKS, IAM |
| **AWS EKS** | Managed Kubernetes cluster |
| **ArgoCD** | GitOps continuous delivery controller |
| **kubectl** | Kubernetes CLI for cluster management |
| **GitHub** | Git repository — source of truth for manifests |
| **nginx** | Sample application deployed via GitOps |
| **AWS Load Balancer** | Exposes ArgoCD UI and nginx app publicly |

---

## Project Structure

```
GitOps-Application-Deployment-with-ArgoCD/
├── terraform/
│   ├── providers.tf          # AWS provider and Terraform version config
│   ├── variables.tf          # Input variables (region, cluster name, etc.)
│   ├── vpc.tf                # VPC, subnets, NAT gateway
│   ├── eks.tf                # EKS cluster and managed node groups
│   └── outputs.tf            # Cluster name, endpoint, region outputs
├── k8s/
│   ├── dev/
│   │   └── deployment.yaml   # nginx Deployment + LoadBalancer Service (dev)
│   └── prod/
│       └── deployment.yaml   # nginx Deployment + LoadBalancer Service (prod)
├── app-definition.yaml       # ArgoCD Application manifest
└── README.md
```

---

## Prerequisites

Before getting started, ensure you have the following installed and configured:

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)
- An AWS account with IAM permissions for EKS, VPC, EC2, and IAM
- A GitHub account with a repository for your manifests

---

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/Samjean50/GitOps-Application-Deployment-with-ArgoCD.git
cd GitOps-Application-Deployment-with-ArgoCD
```

### 2. Configure AWS Credentials

```bash
aws configure
# Enter: Access Key ID, Secret Access Key, Region: us-east-1, Output: json
```

Verify your identity:

```bash
aws sts get-caller-identity
```

---

## Infrastructure Provisioning with Terraform

### 3. Initialise Terraform

```bash
cd terraform/
terraform init
```

### 4. Preview the Infrastructure Plan

```bash
terraform plan
```

This will show all AWS resources to be created: VPC, subnets, NAT gateway, EKS cluster, and managed node groups.

### 5. Provision the Infrastructure

```bash
terraform apply --auto-approve
```

> This takes approximately **15 minutes** to complete. Resources created:
> - VPC with CIDR `10.0.0.0/16`
> - 3 public and 3 private subnets across `us-east-1a`, `us-east-1b`, `us-east-1c`
> - NAT Gateway for private subnet internet access
> - EKS Cluster (`gitops-eks-cluster`) running Kubernetes v1.29
> - Managed Node Group with 2x `t3.medium` instances (scales to 4)

### 6. Connect kubectl to the EKS Cluster

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name gitops-eks-cluster
```

Verify the connection:

```bash
kubectl get nodes
# Expected: 2 nodes with STATUS = Ready
```

---

## ArgoCD Setup

### 7. Install ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for all pods to be running:

```bash
kubectl get pods -n argocd -w
# Press Ctrl+C once all pods show Running
```

### 8. Expose ArgoCD via AWS Load Balancer

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

kubectl get svc argocd-server -n argocd -w
# Wait for EXTERNAL-IP to populate
```

### 9. Get the Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### 10. Login to ArgoCD

Via UI: Open `https://<EXTERNAL-IP>` in your browser (accept SSL warning)
- **Username:** `admin`
- **Password:** from step above

Via CLI:

```bash
argocd login <EXTERNAL-IP> \
  --username admin \
  --password <your-password> \
  --insecure
```

---

## Application Deployment

### 11. Create the ArgoCD Application

The `app-definition.yaml` defines the GitOps application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/Samjean50/GitOps-Application-Deployment-with-ArgoCD.git'
    path: k8s/dev
    targetRevision: HEAD
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Apply it:

```bash
kubectl apply -f app-definition.yaml -n argocd
```

### 12. Sync the Application

```bash
argocd app sync sample-app
```

### 13. Verify the Deployment

```bash
# Check ArgoCD app status
argocd app get sample-app

# Check pods and services
kubectl get all -n default
```

Expected output:
```
NAME                             READY   STATUS    RESTARTS   AGE
pod/sample-app-xxx               1/1     Running   0          2m

NAME                   TYPE           CLUSTER-IP     EXTERNAL-IP
service/nginx-service  LoadBalancer   10.100.x.x     xxxx.us-east-1.elb.amazonaws.com

NAME                        READY   UP-TO-DATE   AVAILABLE
deployment.apps/sample-app  2/2     2            2
```

### 14. Access the nginx App

```bash
kubectl get svc nginx-service -n default
```

Open the `EXTERNAL-IP` in your browser:

```
http://<EXTERNAL-IP>
```

You should see the **nginx Welcome Page** — confirming your GitOps pipeline is working end to end.

---

## GitOps in Action — Testing Automated Sync

One of the core GitOps principles is that any change pushed to Git is automatically reflected in the cluster. Test it:

```bash
# Edit k8s/dev/deployment.yaml — change replicas from 2 to 3
# Then push to GitHub:
git add k8s/dev/deployment.yaml
git commit -m "feat: scale nginx to 3 replicas"
git push origin main
```

ArgoCD will detect the change within 3 minutes and automatically scale your deployment. Watch it happen:

```bash
kubectl get pods -n default -w
```

---

## Application Lifecycle Management

### Syncing

```bash
argocd app sync sample-app
```

### Monitoring Health and Status

```bash
argocd app get sample-app
```

### Performing a Rollback

```bash
argocd app rollback sample-app
```

---

## Repository Structure Best Practices

This project follows GitOps repository best practices:

- **Environment separation** — `k8s/dev/` and `k8s/prod/` directories for different environments
- **Declarative manifests** — all Kubernetes resources defined as YAML
- **Meaningful commits** — conventional commit messages (`feat:`, `fix:`, `chore:`)
- **Version tagging** — use `git tag v1.0.0` for release versioning



## Cleanup

To destroy all AWS infrastructure provisioned by Terraform:

```bash
cd terraform/
terraform destroy --auto-approve
```

## Troubleshooting

**`kubectl get nodes` returns credentials error**
```bash
aws eks update-kubeconfig --region us-east-1 --name gitops-eks-cluster
```

**ArgoCD app shows OutOfSync**
```bash
argocd app sync sample-app --force
```

**No pods found in namespace**
- Check that `app-definition.yaml` has been applied: `kubectl get applications -n argocd`
- Verify the `repoURL` and `path` in your app definition match your GitHub repo

**Service stuck in `<pending>` for EXTERNAL-IP**
- Wait 3-5 minutes for AWS to provision the Load Balancer
- Check AWS console → EC2 → Load Balancers

# STEP-BY-STEP EXECUTION
Below is the practical, command-based execution workflow.

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


## Key Learnings

- GitOps enforces **declarative infrastructure** where Git is the single source of truth
- ArgoCD's **automated sync policy** with `selfHeal: true` ensures the cluster always matches the desired state in Git
- **Terraform modules** (`terraform-aws-modules/eks` and `terraform-aws-modules/vpc`) significantly reduce boilerplate for EKS provisioning
- Separating environments (`dev/`, `prod/`) in the repo enables controlled promotion of changes across environments

