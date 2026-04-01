# =============================================================
# infrastructure/outputs.tf
# PURPOSE: Exposes infrastructure values consumed by pipelines and apps
# NOTICE:  These are outputs about your RUNNING INFRASTRUCTURE
#          cluster endpoints, ECR URLs, IAM role ARNs
#          NOT about bootstrap resources like S3 or DynamoDB
# =============================================================

# ── Cluster ───────────────────────────────────────────────────

output "cluster_name" {
  description = "EKS cluster name — used in pipeline to update kubeconfig"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint — used by Helm and Kubernetes providers"
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN — used by iam.tf to create IRSA roles"
  value       = module.eks.oidc_provider_arn
}

# ── Networking ────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID — used by Load Balancer Controller"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs — used by node groups and pods"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs — used by load balancers"
  value       = module.vpc.public_subnets
}

# ── ECR ───────────────────────────────────────────────────────

output "ecr_eshop_url" {
  description = "ECR URL for the eshop app — used in build-deploy pipeline"
  value       = aws_ecr_repository.eshop.repository_url
}

output "ecr_chatbot_url" {
  description = "ECR URL for the chatbot — used in build-deploy pipeline"
  value       = aws_ecr_repository.chatbot.repository_url
}

# ── IRSA role ARNs ────────────────────────────────────────────
# These are injected into Helm releases in addons.tf
# They are NEVER hardcoded in ArgoCD app manifests

output "lbc_irsa_role_arn" {
  description = "IAM role for AWS Load Balancer Controller"
  value       = module.lbc_irsa.iam_role_arn
}

output "eso_irsa_role_arn" {
  description = "IAM role for External Secrets Operator"
  value       = module.eso_irsa.iam_role_arn
}

output "cluster_autoscaler_irsa_role_arn" {
  description = "IAM role for Cluster Autoscaler"
  value       = module.cluster_autoscaler_irsa.iam_role_arn
}
