# =============================================================
# iam.tf — IRSA roles for EKS add-ons
# =============================================================
# NOTE: The following resources are managed by bootstrap/ NOT here:
#   - aws_iam_openid_connect_provider.github  (GitHub OIDC provider)
#   - aws_iam_role.github_actions             (GitHub Actions role)
#   - aws_iam_role_policy.github_actions      (GitHub Actions permissions)
#
# This file only manages IRSA roles for EKS add-ons
# =============================================================

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
