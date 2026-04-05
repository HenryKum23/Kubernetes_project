# =============================================================
# infrastructure/main.tf
# PURPOSE: Creates your actual project infrastructure on AWS
# WHEN:    Runs automatically via GitHub Actions pipeline on every PR/merge
# STATE:   Stored REMOTELY in S3 (created by bootstrap)
# CREATES: VPC, EKS cluster, node groups, providers
# DEPENDS ON: bootstrap must have run first
# ==============================================================

# =============================================================
# main.tf — VPC and EKS cluster
# ============================================================

# ── Providers ─────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      environment = var.environment
      team        = "devops"
      project     = "eshop"
      managed_by  = "terraform"
    }
  }
}

# Helm provider — uses EKS cluster credentials to install Helm charts
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# Kubernetes provider — used to apply the ArgoCD App of Apps manifest
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# ── What this file creates ────────────────────────────────────

# 1. VPC — private network for your cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true   # One NAT to save costs — change to false for full HA
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Mandatory tags — EKS uses these to discover which subnets to use for load balancers
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# 2. EKS cluster — your managed Kubernetes cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true  # Required for IRSA (pod-level IAM permissions)

  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  # Managed add-ons — AWS manages these, they update automatically
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = {
      most_recent              = true
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Worker nodes
  eks_managed_node_groups = {
    app-nodes = {
      instance_types = [var.node_instance_type]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      disk_size      = 20
      subnet_ids     = module.vpc.private_subnets
      labels = {
        role        = "app"
        environment = var.environment
      }
    }
  }

  # Allow the GitHub Actions role (created by bootstrap) to manage the cluster
  access_entries = {
    github_actions = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/henry-eks-github-actions-role"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

data "aws_caller_identity" "current" {}
