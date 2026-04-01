# =============================================================
# iam.tf — All IAM roles in one place
# Replaces the iam block in cluster_config.yml
# Replaces long-lived AWS keys with OIDC federation
# =============================================================

# =============================================================
# GITHUB ACTIONS OIDC — replaces AWS_ACCESS_KEY_ID secrets
# GitHub assumes this role directly — no keys stored anywhere
# =============================================================

# Trust the GitHub OIDC provider
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# If the GitHub OIDC provider doesn't exist yet, create it
resource "aws_iam_openid_connect_provider" "github" {
  count = 1

  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# IAM role that GitHub Actions assumes via OIDC
resource "aws_iam_role" "github_actions" {
  name = "github-actions-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # Scope to your specific repository only
            "token.actions.githubusercontent.com:sub" = "repo:HenryKum23/Kubernetes_project:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Permissions the GitHub Actions role needs
resource "aws_iam_role_policy" "github_actions" {
  name = "github-actions-eks-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # EKS — create, update, describe cluster
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = "*"
      },
      {
        # EC2 — needed for VPC and node group management
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      },
      {
        # IAM — needed for creating IRSA roles
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:PassRole",
          "iam:TagRole",
          "iam:CreateOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider"
        ]
        Resource = "*"
      },
      {
        # S3 — Terraform state backend
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::henry-eks-terraform-state",
          "arn:aws:s3:::henry-eks-terraform-state/*"
        ]
      },
      {
        # DynamoDB — Terraform state locking
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:us-east-1:*:table/henry-eks-terraform-locks"
      },
      {
        # ECR — push and pull images
        Effect = "Allow"
        Action = ["ecr:*"]
        Resource = "*"
      },
      {
        # CloudWatch — cluster logging
        Effect = "Allow"
        Action = ["logs:*"]
        Resource = "*"
      },
      {
        # Auto Scaling — node groups
        Effect   = "Allow"
        Action   = ["autoscaling:*"]
        Resource = "*"
      }
    ]
  })
}

# =============================================================
# IRSA ROLES — replaces iam.serviceAccounts in cluster_config.yml
# Each add-on gets its own role with least-privilege permissions
# Role names are clean and readable — not eksctl-generated random strings
# =============================================================

# VPC CNI IRSA
module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-vpc-cni-irsa"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
}

# EBS CSI Driver IRSA
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi-irsa"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# AWS Load Balancer Controller IRSA
module "lbc_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-lbc-irsa"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# Cluster Autoscaler IRSA
module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                        = "${var.cluster_name}-cluster-autoscaler-irsa"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

# External Secrets Operator IRSA
# Custom policy — no built-in policy exists for Secrets Manager
module "eso_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-eso-irsa"

  role_policy_arns = {
    policy = aws_iam_policy.eso_secrets_manager.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets-sa"]
    }
  }
}

# Least-privilege policy for ESO — only the one secret it needs
resource "aws_iam_policy" "eso_secrets_manager" {
  name        = "${var.cluster_name}-eso-secrets-manager-policy"
  description = "Allows External Secrets Operator to read Anthropic API key"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Scoped to only the Anthropic secret — least privilege
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.anthropic_secret_name}-*"
      }
    ]
  })
}
