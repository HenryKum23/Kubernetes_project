# Production EKS Deployment — Eshop & AI Chatbot on AWS

A complete GitOps-based deployment of a Node.js/Express eshop with an AI-powered chatbot on AWS EKS, using ArgoCD, GitHub Actions, External Secrets Operator, and a fully automated CI/CD pipeline.

**Live:** [https://henrykumahconsult.org](https://henrykumahconsult.org)
**GitHub:** [https://github.com/HenryKum23/Kubernetes_project](https://github.com/HenryKum23/Kubernetes_project)

---

## Table of Contents

- [Project Overview](#project-overview)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Infrastructure](#infrastructure)
- [GitOps with ArgoCD](#gitops-with-argocd)
- [CI/CD Pipeline](#cicd-pipeline)
- [Application](#application)
- [Secret Management](#secret-management)
- [Networking & DNS](#networking--dns)
- [Order of Operations](#order-of-operations)
- [Security](#security)
- [GitHub Secrets Required](#github-secrets-required)
- [Estimated Cost](#estimated-cost)

---

## Project Overview

This project provisions and deploys a production-grade Kubernetes cluster on AWS EKS using a fully declarative, GitOps-driven approach. Every component — from infrastructure provisioning to application deployment — is defined as code and version-controlled in this repository.

> **GitOps Principle:** The GitHub repository is the single source of truth. No manual `kubectl` commands are run after the initial bootstrap. All changes go through Git.

The application is a Node.js/Express eshop that serves static HTML, CSS, and JavaScript from a `public/` directory. It runs alongside an AI-powered chatbot service integrated with the Anthropic Claude API, with secrets managed at runtime through AWS Secrets Manager — never stored in Git.

---

## Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| Cloud Provider | AWS | All infrastructure hosted on AWS |
| Container Orchestration | Amazon EKS (Kubernetes 1.29) | Runs and manages application pods |
| Cluster Provisioning | eksctl | Provisions the EKS cluster from YAML config |
| Container Registry | AWS ECR | Stores Docker images with vulnerability scanning |
| GitOps / CD | ArgoCD | Syncs Git repo state to the cluster automatically |
| CI Pipeline | GitHub Actions | Builds, tests, scans, and pushes Docker images |
| Secret Management | External Secrets Operator + AWS Secrets Manager | Runtime secret injection — zero secrets in Git |
| Load Balancing | AWS Load Balancer Controller | Creates and manages AWS ALB from Ingress resources |
| DNS Management | AWS Route 53 + Namecheap | Custom domain with nameserver delegation to AWS |
| SSL/TLS | AWS Certificate Manager | HTTPS with automatic HTTP → HTTPS redirect |
| Security Scanning | Trivy | Blocks deployment on CRITICAL/HIGH CVEs |
| AI Integration | Anthropic Claude API | Powers the eshop chatbot service |

---

## Repository Structure

```
eshop_project/
├── cluster_config.yml                     # eksctl cluster definition
├── argocd-app-of-apps.yml                 # ArgoCD App of Apps — root controller
├── .github/
│   └── workflows/
│       ├── infra.yml                      # Provisions cluster + installs ArgoCD
│       └── build-and-deploy.yml           # CI pipeline — build, scan, push images
├── infrastructure/
│   └── ecr.yml                            # ECR repository definition
├── bootstrap/
│   └── argocd-install.yml                 # ArgoCD bootstrap manifest
├── app/                                   # Eshop Node.js/Express application
│   ├── public/                            # HTML, CSS, JavaScript files
│   ├── server.js                          # Express server (port 3000)
│   ├── package.json
│   ├── package-lock.json
│   ├── Dockerfile
│   └── chatbot/                           # AI chatbot service
│       ├── server.js                      # Chatbot Express server (port 4000)
│       ├── package.json
│       └── Dockerfile
└── apps/                                  # ArgoCD watches this entire folder
    ├── aws-load-balancer-controller/
    │   └── application.yml                # ArgoCD app — installs ALB controller
    ├── cluster-autoscaler/
    │   └── application.yml                # ArgoCD app — installs cluster autoscaler
    ├── external-secrets/
    │   └── application.yml                # ArgoCD app — installs ESO
    └── my-app/                            # Eshop Kubernetes manifests
        ├── application.yml                # ArgoCD app — deploys the eshop
        ├── namespace.yml
        ├── deployment.yml
        ├── chatbot-deployment.yml
        ├── service.yml
        ├── chatbot-service.yml
        ├── ingress.yml
        ├── secret-store.yml               # ClusterSecretStore — connects to AWS Secrets Manager
        └── external-secret.yml            # Pulls Anthropic API key into Kubernetes secret
```

---

## Infrastructure

### EKS Cluster — eksctl

The cluster is defined in `cluster_config.yml` and provisioned via the `infra.yml` pipeline. It is lean but production-structured — right-sized for a lightweight application while following AWS best practices.

| Configuration | Value | Reason |
|---|---|---|
| Kubernetes Version | 1.29 | Pinned — no surprise upgrades |
| Region | us-east-1 | AWS primary region |
| Availability Zones | us-east-1a, us-east-1b | 2 AZs for HA without excessive cost |
| Node Instance Type | t3.small | Cost-effective for a lightweight app |
| Node Count | 2 desired, min 1, max 3 | Basic HA with cluster autoscaler |
| Networking | Private subnets only | Nodes not directly accessible from internet |
| NAT Gateway | Single | Cost-saving for a project environment |
| OIDC | Enabled | Required for IRSA — pods get AWS permissions without hardcoded keys |
| SSH Access | Disabled | SSM Session Manager used instead |
| CloudWatch Logs | api, audit, authenticator | Essential control plane logs only |
| Log Retention | 7 days | Sufficient for project, reduces cost |

### IAM Service Accounts (IRSA)

OIDC is enabled on the cluster so Kubernetes Service Accounts can assume AWS IAM roles directly. This is the production-standard approach — no hardcoded credentials anywhere.

| Service Account | Namespace | AWS Permission |
|---|---|---|
| aws-load-balancer-controller | kube-system | Create and manage AWS Load Balancers |
| cluster-autoscaler | kube-system | Scale EC2 Auto Scaling Groups |
| ebs-csi-controller-sa | kube-system | Create and attach EBS volumes |
| external-secrets-sa | external-secrets | Read secrets from AWS Secrets Manager |

### EKS Addons

| Addon | Purpose |
|---|---|
| vpc-cni | Pod networking — assigns VPC IP addresses to pods |
| coredns | Internal DNS resolution within the cluster |
| kube-proxy | Manages network rules on each node |

---

## GitOps with ArgoCD

### App of Apps Pattern

The entire cluster is bootstrapped from a single manifest — `argocd-app-of-apps.yml`. This tells ArgoCD to watch the `apps/` folder and manage everything inside it automatically.

```
argocd-app-of-apps.yml  (root — watches apps/ folder)
        ↓
apps/aws-load-balancer-controller/application.yml  → installs ALB controller
apps/cluster-autoscaler/application.yml            → installs cluster autoscaler
apps/external-secrets/application.yml              → installs External Secrets Operator
apps/my-app/application.yml                        → deploys eshop + chatbot
```

After the initial bootstrap, no further `kubectl apply` commands are ever needed. Push to Git — ArgoCD handles the rest.

### Sync Policy

All ArgoCD applications use automated sync:

| Policy | Value | Effect |
|---|---|---|
| automated.prune | true | Resources deleted from Git are removed from cluster |
| automated.selfHeal | true | Manual changes in cluster are auto-reverted |
| syncOptions.CreateNamespace | true | Namespaces created automatically if missing |

---

## CI/CD Pipeline

### Two Separate Pipelines

| Pipeline | File | Trigger | Purpose |
|---|---|---|---|
| Infra | `infra.yml` | Manual (`workflow_dispatch`) | Provision cluster + install ArgoCD |
| App | `build-and-deploy.yml` | Push to `app/**` | Build, scan, push images + update manifests |

> **CI = GitHub Actions** (build, test, scan, push)
> **CD = ArgoCD** (detect manifest change → deploy automatically)

### App Pipeline Steps

| Step | Action |
|---|---|
| 1 | Checkout code |
| 2 | Setup Node.js 18 with dependency caching |
| 3 | Install and test eshop |
| 4 | Install and test chatbot |
| 5 | Configure AWS credentials |
| 6 | Create ECR repositories if not exists |
| 7 | Login to ECR |
| 8 | Build eshop Docker image (tagged with git SHA + latest) |
| 9 | Build chatbot Docker image |
| 10 | Trivy scan — blocks on CRITICAL/HIGH CVEs |
| 11 | Push both images to ECR |
| 12 | Update image tags in deployment manifests |
| 13 | Commit updated manifests `[skip ci]` → ArgoCD deploys |

### Quality Gate

```
Code pushed to app/
        ↓
Tests pass?          NO  → pipeline fails ❌
        ↓ YES
Images built
        ↓
CVEs found?          YES → pipeline fails ❌
        ↓ NO
Images pushed to ECR
        ↓
Manifests updated in Git
        ↓
ArgoCD detects change → deploys automatically ✅
```

---

## Application

### Eshop (port 3000)
A Node.js/Express application serving static HTML, CSS, and JavaScript from the `public/` directory.

### AI Chatbot (port 4000)
A separate Node.js service that integrates with the Anthropic Claude API to power an AI assistant embedded in the eshop. The Anthropic API key is never hardcoded — it is injected at runtime from AWS Secrets Manager via External Secrets Operator.

### Kubernetes Manifests

| Manifest | Kind | Purpose |
|---|---|---|
| namespace.yml | Namespace | Isolated environment — my-app namespace |
| deployment.yml | Deployment | Eshop — 2 replicas, pulls image from ECR |
| chatbot-deployment.yml | Deployment | Chatbot — 1 replica, pulls image from ECR |
| service.yml | Service (ClusterIP) | Internal routing to eshop pods on port 3000 |
| chatbot-service.yml | Service (ClusterIP) | Internal routing to chatbot pods on port 4000 |
| ingress.yml | Ingress | Exposes app via AWS ALB with SSL termination |
| secret-store.yml | ClusterSecretStore | Connects ESO to AWS Secrets Manager |
| external-secret.yml | ExternalSecret | Pulls Anthropic API key into Kubernetes secret |

---

## Secret Management

Secrets are managed using the External Secrets Operator (ESO) with IRSA — a production-standard approach where no secret value ever touches Git.

```
AWS Secrets Manager (floma/anthropic-api-key)
        ↓
External Secrets Operator (IRSA — uses external-secrets-sa)
        ↓
ClusterSecretStore (cluster-wide — serves all namespaces)
        ↓
ExternalSecret (my-app namespace)
        ↓
Kubernetes Secret: anthropic-secret
        ↓
Chatbot pod reads ANTHROPIC_API_KEY at runtime
```

To store the API key in AWS Secrets Manager:
```bash
aws secretsmanager create-secret \
  --name floma/anthropic-api-key \
  --secret-string '{"ANTHROPIC_API_KEY":"your-key-here"}' \
  --region us-east-1
```

---

## Networking & DNS

### Traffic Flow

```
User visits https://henrykumahconsult.org
        ↓
Namecheap nameservers → AWS Route 53
        ↓
Route 53 A Alias record → AWS ALB
        ↓
ALB (HTTP → HTTPS redirect, ACM certificate)
        ↓
Ingress (host: henrykumahconsult.org)
        ↓
Service: eshop-service (ClusterIP, port 80 → 3000)
        ↓
Eshop pod (Node.js/Express, port 3000)
        ↓
User sees eshop ✅
```

### DNS Setup

| Component | Configuration |
|---|---|
| Domain Registrar | Namecheap |
| DNS Provider | AWS Route 53 (nameservers delegated from Namecheap) |
| Record Type | A Alias → ALB (recommended over CNAME for root domain) |
| SSL Certificate | AWS Certificate Manager (DNS validation via Route 53) |
| HTTP Redirect | ALB listener rule — 301 redirect HTTP → HTTPS |

---

## Order of Operations

| # | Step | How | When |
|---|---|---|---|
| 1 | Add GitHub Secrets | GitHub → Settings → Secrets | Once |
| 2 | Store API key in AWS Secrets Manager | AWS CLI or Console | Once |
| 3 | Trigger infra pipeline | Actions → Provision Infrastructure → Run workflow | Once |
| 4 | ArgoCD installs all addons | Automatic via App of Apps | Automatic |
| 5 | ArgoCD deploys eshop + chatbot | Automatic | Automatic |
| 6 | Create Route 53 hosted zone | AWS CLI | Once |
| 7 | Update Namecheap nameservers | Namecheap dashboard | Once |
| 8 | Request ACM certificate | AWS CLI | Once |
| 9 | Future deployments | `git push origin main` | Every deploy |

### Teardown
```bash
# Delete the cluster when not in use to save costs
eksctl delete cluster --name prod-cluster --region us-east-1

# Verify deletion
aws eks describe-cluster --name prod-cluster --region us-east-1
```

---

## Security

| Area | Measure | Detail |
|---|---|---|
| Nodes | Private subnets | Worker nodes have no direct internet access |
| SSH | Disabled | SSM Session Manager used instead |
| Secrets | External Secrets Operator + IRSA | No secrets ever stored in Git |
| Images | Trivy scanning | CRITICAL/HIGH CVEs block deployment |
| Images | ECR scan on push | Additional scan when image arrives in registry |
| IAM | IRSA | Pods get minimum required AWS permissions only |
| TLS | ACM certificate | HTTPS enforced — HTTP redirected to HTTPS |
| Credentials | GitHub Secrets | AWS keys never hardcoded in code |

---

## GitHub Secrets Required

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `GITHUB_TOKEN` | Auto-provided by GitHub Actions |

---

## Estimated Cost

| Resource | Specification | Approx Monthly Cost |
|---|---|---|
| EKS Control Plane | Managed by AWS | $72.00 |
| EC2 Worker Nodes | 2x t3.small | $30.00 |
| NAT Gateway | Single | $32.00 |
| EBS Volumes | 2x 20GB gp3 | $3.20 |
| ECR Storage | Images stored | ~$1.00 |
| CloudWatch Logs | 7 day retention | ~$2.00 |
| Route 53 | Hosted zone | ~$0.50 |
| **Total (running 24/7)** | | **~$141/month** |

> **Cost tip:** Delete the cluster when not actively using it. The EKS control plane alone costs $2.40/day. Running only during active development can reduce costs by 80% or more.
