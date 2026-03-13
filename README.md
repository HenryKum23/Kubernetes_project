# EKS Production Cluster — Eshop Deployment

A complete GitOps-based deployment of a Node.js/Express eshop application on AWS EKS using ArgoCD, GitHub Actions, and CloudFormation.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Infrastructure](#infrastructure)
- [GitOps with ArgoCD](#gitops-with-argocd)
- [CI/CD Pipeline](#cicd-pipeline)
- [Application](#application)
- [Order of Operations](#order-of-operations)
- [Security](#security)
- [Automated Dependency Updates](#automated-dependency-updates)
- [Addons Not Included](#addons-not-included)
- [Estimated Cost](#estimated-cost)

---

## Project Overview

This project provisions and deploys a production-grade Kubernetes cluster on AWS EKS using a fully declarative, GitOps-driven approach. Every component — from infrastructure provisioning to application deployment — is defined as code and version-controlled in this repository.

> **GitOps Principle:** The GitHub repository is the single source of truth. No manual `kubectl` commands are run after the initial bootstrap. All changes go through Git.

The application is a Node.js/Express eshop that serves static HTML, CSS and JavaScript files from a `public/` directory. It listens on port 3000 and is containerised using Docker with a hardened multi-stage build.

---

## Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| Cloud Provider | AWS | All infrastructure hosted on AWS |
| Container Orchestration | Amazon EKS (Kubernetes) | Runs and manages application pods |
| Cluster Provisioning | eksctl | Provisions the EKS cluster from YAML config |
| Infrastructure as Code | AWS CloudFormation | Creates ECR repository |
| Container Registry | AWS ECR | Stores Docker images |
| GitOps / CD | ArgoCD | Syncs Git repo state to the cluster |
| CI Pipeline | GitHub Actions | Builds, tests and pushes Docker images |
| Web Server | Node.js + Express | Serves the eshop application |
| DNS Management | AWS Route53 | Routes domain traffic to Load Balancer |
| Domain Registrar | GoDaddy → Route53 | Custom domain nameservers delegated to AWS |
| Security Scanning | Trivy | Scans Docker images for vulnerabilities |
| Dependency Updates | Dependabot | Keeps npm, Docker and Actions up to date |

---

## Repository Structure

```
eks-production-app/
├── cluster-config.yaml                  # eksctl cluster definition
├── argocd-app-of-apps.yaml              # ArgoCD App of Apps — master controller
├── .github/
│   └── workflows/
│       └── build-and-deploy.yaml        # GitHub Actions CI pipeline
├── infrastructure/
│   ├── ecr.yaml                         # CloudFormation — creates ECR repo
│   └── README.md
├── bootstrap/
│   └── argocd-install.yaml              # Installs ArgoCD into the cluster
├── app/                                 # Node.js/Express eshop application
│   ├── public/                          # HTML, CSS, JavaScript files
│   ├── server.js                        # Express server
│   ├── package.json
│   ├── package-lock.json
│   ├── Dockerfile                       # Hardened multi-stage Docker image
│   └── .dockerignore
└── apps/
    ├── aws-load-balancer-controller/
    │   └── application.yaml             # ArgoCD app for ALB controller
    ├── cluster-autoscaler/
    │   └── application.yaml             # ArgoCD app for autoscaler
    └── my-app/
        ├── namespace.yaml
        ├── configmap.yaml
        ├── deployment.yaml
        ├── service.yaml
        └── ingress.yaml
```

---

## Infrastructure

### ECR Repository — CloudFormation

The ECR repository is created before the cluster using a CloudFormation template. This ensures the image registry exists before GitHub Actions attempts to push Docker images.

| Feature | Configuration | Reason |
|---|---|---|
| Image Scanning | ScanOnPush: true | Every pushed image scanned for CVEs automatically |
| Lifecycle Policy | Keep last 10 images | Older images deleted to control storage costs |
| Encryption | AES256 | Images encrypted at rest |
| Stack Name | eshop-ecr | CloudFormation manages resource lifecycle |

```bash
aws cloudformation deploy \
  --template-file infrastructure/ecr.yaml \
  --stack-name eshop-ecr \
  --region us-east-1
```

### EKS Cluster — eksctl

The cluster is defined in `cluster-config.yaml` and provisioned using eksctl. It is lean but production-structured — right-sized for a lightweight application while following all production best practices.

| Configuration | Value | Reason |
|---|---|---|
| Kubernetes Version | 1.29 | Pinned version — no surprise upgrades |
| Region | us-east-1 | AWS primary region |
| Availability Zones | us-east-1a, us-east-1b | 2 AZs for HA without excessive cost |
| Node Instance Type | t3.medium | 2 vCPU / 4GB RAM — sufficient for lightweight app |
| Node Count | 2 desired, min 1, max 3 | Basic HA with auto-scaling |
| Networking | Private subnets only | Nodes not directly accessible from internet |
| NAT Gateway | Single | Cost-saving — one NAT gateway |
| OIDC | Enabled | Required for IAM Roles for Service Accounts |
| SSH Access | Disabled | SSM Session Manager used instead |
| CloudWatch Logs | api, audit, authenticator | Essential control plane logs only |
| Log Retention | 7 days | Sufficient for project, reduces cost |

### IAM Service Accounts (IRSA)

OIDC is enabled on the cluster to allow Kubernetes Service Accounts to assume AWS IAM roles. This is the secure, production-standard way for pods to interact with AWS services without hardcoding credentials.

| Service Account | Namespace | AWS Permission | Used By |
|---|---|---|---|
| aws-load-balancer-controller | kube-system | Create/manage AWS Load Balancers | ALB Controller pod |
| cluster-autoscaler | kube-system | Scale EC2 Auto Scaling Groups | Autoscaler pod |
| ebs-csi-controller-sa | kube-system | Create/attach EBS volumes | EBS CSI Driver pod |

### EKS Addons

Core cluster infrastructure is managed as EKS addons directly in `cluster-config.yaml`. These are distinct from application-level controllers managed by ArgoCD.

| Addon | Purpose |
|---|---|
| vpc-cni | Pod networking — assigns VPC IP addresses to pods |
| coredns | Internal DNS resolution within the cluster |
| kube-proxy | Manages network rules on each node |
| aws-ebs-csi-driver | Allows pods to use EBS volumes for persistent storage |

---

## GitOps with ArgoCD

### App of Apps Pattern

The project uses the ArgoCD App of Apps pattern. A single master ArgoCD Application (`argocd-app-of-apps.yaml`) watches the `/apps` folder in the repository. Any Application manifest found there is automatically managed by ArgoCD.

```
argocd-app-of-apps.yaml  (master — watches /apps folder)
        ↓
apps/aws-load-balancer-controller/application.yaml
apps/cluster-autoscaler/application.yaml
apps/my-app/  (deployment, service, ingress, namespace, configmap)
```

### Sync Policy

All ArgoCD applications are configured with automated sync:

| Policy | Value | Effect |
|---|---|---|
| automated.prune | true | Resources deleted from Git are removed from cluster |
| automated.selfHeal | true | Manual changes in cluster are auto-reverted |
| syncOptions.CreateNamespace | true | Namespaces created automatically if missing |

### Namespace Isolation

Every application runs in its own dedicated namespace:

| Namespace | Contents |
|---|---|
| kube-system | All Kubernetes system components and controllers |
| argocd | ArgoCD itself — manages all other applications |
| my-app | The eshop application — deployment, service, ingress |

Pods communicate across namespaces using Kubernetes internal DNS:
```
service-name.namespace.svc.cluster.local
```

---

## CI/CD Pipeline

GitHub Actions handles the CI side of the pipeline. It triggers automatically on every push to `main` when files in the `app/` folder change.

> **CI = GitHub Actions** (build, test, push image) **CD = ArgoCD** (deploy to cluster)

### Pipeline Steps

| Step | Action | Why |
|---|---|---|
| 1 | Checkout code | Gets latest code from GitHub |
| 2 | Setup Node.js 18 | Correct runtime version with dependency caching |
| 3 | npm install + npm test | Broken code never reaches ECR or production |
| 4 | Configure AWS credentials | Authenticates with AWS using GitHub Secrets |
| 5 | Check ECR exists | Creates ECR via CloudFormation if not present |
| 6 | Login to ECR | Authorises Docker to push to private registry |
| 7 | Build Docker image | Packages app with git SHA and latest tags |
| 8 | Trivy vulnerability scan | Blocks deployment if CRITICAL or HIGH CVEs found |
| 9 | Push image to ECR | Stores verified image in registry |
| 10 | Update deployment.yaml | Writes new image tag into Kubernetes manifest |
| 11 | Commit and push [skip ci] | Triggers ArgoCD to deploy — [skip ci] prevents loop |

### Quality Gate

```
Code pushed
    ↓
Tests pass?         NO  → pipeline fails ❌
    ↓ YES
Image built
    ↓
Vulnerabilities?    YES → pipeline fails ❌
    ↓ NO
Image pushed to ECR
    ↓
ArgoCD deploys ✅
```

### Image Tagging Strategy

| Tag | Example | Purpose |
|---|---|---|
| git SHA | my-app:a3f8c2d | Unique, immutable — enables precise rollback |
| latest | my-app:latest | Always points to most recent successful build |

---

## Application

### Hardened Dockerfile — Multi-Stage Build

| Hardening Measure | Implementation | Security Benefit |
|---|---|---|
| Multi-stage build | Builder + final stage | No build tools in production image |
| Non-root user | adduser appuser | Limits blast radius if container is compromised |
| Read-only permissions | chmod -R 550 | App cannot modify its own files |
| Strict dependencies | npm ci --only=production | Reproducible, no dev dependencies |
| Health check | wget localhost:3000 | Kubernetes restarts unhealthy pods automatically |
| Exec form CMD | CMD ["node", "server.js"] | No shell process — reduces attack surface |

### Kubernetes Manifests

| Manifest | Kind | Purpose |
|---|---|---|
| namespace.yaml | Namespace | Isolated environment for the eshop app |
| configmap.yaml | ConfigMap | Stores configuration data for the app |
| deployment.yaml | Deployment | Runs 2 replicas, pulls image from ECR |
| service.yaml | Service (ClusterIP) | Internal routing to app pods on port 3000 |
| ingress.yaml | Ingress | Exposes app via AWS ALB on yourdomain.com |

### Traffic Flow

```
User types yourdomain.com in browser
    ↓
GoDaddy nameservers → AWS Route53
    ↓
Route53 resolves to AWS Load Balancer
    ↓
AWS ALB (created by aws-load-balancer-controller)
    ↓
Ingress (routes by host: yourdomain.com)
    ↓
Service (ClusterIP — routes to pods on port 3000)
    ↓
Pod running Node.js/Express (server.js)
    ↓
Express serves index.html from public/ folder
    ↓
User sees eshop ✅
```

---

## Order of Operations

The following sequence must be followed exactly. Each step depends on the previous one being complete.

| # | Step | Command | Run |
|---|---|---|---|
| 1 | Create ECR repository | `aws cloudformation deploy --template-file infrastructure/ecr.yaml --stack-name eshop-ecr --region us-east-1` | Once |
| 2 | Provision EKS cluster | `eksctl create cluster -f cluster-config.yaml` | Once |
| 3 | Update kubeconfig | `aws eks update-kubeconfig --name prod-cluster --region us-east-1` | Once |
| 4 | Install ArgoCD | `kubectl apply -f bootstrap/argocd-install.yaml` | Once |
| 5 | Apply App of Apps | `kubectl apply -f argocd-app-of-apps.yaml` | Once |
| 6 | ArgoCD installs controllers | Automatic | Automatic |
| 7 | ArgoCD deploys eshop | Automatic | Automatic |
| 8 | Configure Route53 | Create hosted zone, update GoDaddy nameservers | Once |
| 9 | Future deployments | `git push origin main` | Every deploy |

### Teardown
```bash
# Delete the cluster when not in use to save costs
eksctl delete cluster -f cluster-config.yaml

# Delete ECR stack
aws cloudformation delete-stack --stack-name eshop-ecr --region us-east-1
```

---

## Security

### Security Measures

| Area | Measure | Detail |
|---|---|---|
| Nodes | Private subnets | Worker nodes have no direct internet access |
| SSH | Disabled | SSM Session Manager used instead |
| Container | Non-root user | App runs as appuser, not root |
| Container | Read-only filesystem | chmod 550 on all app files |
| Images | Trivy scanning | CRITICAL/HIGH CVEs block deployment |
| Images | ECR scan on push | Additional scan when image arrives in registry |
| Credentials | GitHub Secrets | AWS keys never hardcoded in code |
| IAM | IRSA | Pods get minimum required AWS permissions only |

### GitHub Secrets Required

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key with ECR and CloudFormation permissions |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret key |

---

## Automated Dependency Updates

Dependabot automatically opens Pull Requests when updates are available:

| Ecosystem | Directory | What it watches | Schedule |
|---|---|---|---|
| npm | /app | All packages in package.json | Weekly |
| github-actions | / | actions/checkout, aws-actions/* | Weekly |
| docker | /app | node:18-alpine base image | Weekly |

---

## Addons Not Included

The following were deliberately excluded to keep the project lean and cost-effective. They represent the natural next steps when scaling to a fully enterprise-grade setup.

### KMS Secrets Encryption
Encrypts Kubernetes secrets stored in etcd at rest. Without it, secrets are only base64 encoded — not truly encrypted.
**When to add:** When the application handles sensitive data that must meet compliance requirements (PCI-DSS, HIPAA, SOC2).

### ExternalDNS
Automatically manages Route53 DNS records based on Ingress annotations. Without it, DNS records must be updated manually whenever the Load Balancer URL changes.
**When to add:** When you want fully automated DNS management tied to your domain.

### Cert-Manager + TLS/HTTPS
Automatically provisions and renews TLS certificates from Let's Encrypt, enabling HTTPS.
**When to add:** Before making the application publicly accessible to real users. HTTPS is a baseline requirement for any production web application.

### Prometheus + Grafana — Monitoring
Full observability into cluster and application health — CPU, memory, request latency, error rates, pod restarts.
**When to add:** As soon as the application goes live. Without monitoring there is no visibility into what is happening in the cluster.

### Centralised Logging — Loki or ELK
Aggregates logs from all pods into a single searchable interface.
**When to add:** When debugging production issues where logs from multiple pods need to be correlated.

| Option | Components | Best For |
|---|---|---|
| Loki Stack | Loki + Promtail + Grafana | Lightweight clusters already using Grafana |
| ELK Stack | Elasticsearch + Logstash + Kibana | Large clusters with high log volume |

### Velero — Backup and Disaster Recovery
Backs up Kubernetes resources and persistent volumes to S3.
**When to add:** When the cluster holds stateful workloads or data that must survive accidental deletion or cluster failure.

### Horizontal Pod Autoscaler (HPA)
Scales pod replicas based on CPU or memory usage. Works alongside Cluster Autoscaler — HPA scales pods, Cluster Autoscaler scales nodes.
**When to add:** When the application receives variable traffic.

### Network Policies
Restricts which pods can communicate with each other. By default all pods across all namespaces can communicate freely.
**When to add:** In a multi-team environment or when compliance mandates network segmentation.

### Highly Available NAT Gateway
This project uses a Single NAT Gateway. A full enterprise setup uses one NAT Gateway per AZ.

| Configuration | Cost | Availability |
|---|---|---|
| Single NAT Gateway (this project) | ~$32/month | Single point of failure |
| HighlyAvailable (3x NAT Gateway) | ~$96/month | No single point of failure |

---

## Estimated Cost

| Resource | Specification | Approx Monthly Cost |
|---|---|---|
| EKS Control Plane | Managed by AWS | $72.00 |
| EC2 Worker Nodes | 2x t3.medium | $60.00 |
| NAT Gateway | Single | $32.00 |
| EBS Volumes | 2x 20GB gp3 | $3.20 |
| ECR Storage | Last 10 images | ~$1.00 |
| CloudWatch Logs | 7 day retention | ~$2.00 |
| **Total (running 24/7)** | | **~$170/month** |

> **Cost tip:** Delete the cluster when not in use. The EKS control plane alone costs $2.40/day. Running only during active development can reduce costs by 80% or more.