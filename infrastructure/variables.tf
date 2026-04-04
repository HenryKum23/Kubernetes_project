# =============================================================
# infrastructure/variables.tf
# PURPOSE: Inputs for your actual project infrastructure
# NOTICE:  These variables are about WHAT to build
#          cluster size, networking, versions, domain name
#          They are NOT about who runs it or where state lives
# =============================================================

variable "aws_region" {
  description = "AWS region for all infrastructure resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment — used in resource tags"
  type        = string
  default     = "production"
}

# ── Cluster ───────────────────────────────────────────────────

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "prod-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}

# ── Networking ────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to deploy into"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs — nodes, pods, and databases live here"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs — load balancers only"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

# ── Node group ────────────────────────────────────────────────

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Desired number of worker nodes at startup"
  type        = number
  default     = 2
}

# ── Application ───────────────────────────────────────────────

variable "domain_name" {
  description = "Primary domain name for the eshop application"
  type        = string
  default     = "henrykumahconsult.org"
}

variable "anthropic_secret_name" {
  description = "Name of the Anthropic API key in AWS Secrets Manager"
  type        = string
  default     = "floma/anthropic-api-key"
}

# ── Helm chart versions — all pinned, never latest ────────────

variable "argocd_chart_version" {
  description = "Pinned ArgoCD Helm chart version"
  type        = string
  default     = "7.7.11"
}

variable "lbc_chart_version" {
  description = "Pinned AWS Load Balancer Controller chart version"
  type        = string
  default     = "1.14.0"
}

variable "eso_chart_version" {
  description = "Pinned External Secrets Operator chart version"
  type        = string
  default     = "0.9.20"
}

variable "cluster_autoscaler_chart_version" {
  description = "Pinned Cluster Autoscaler chart version"
  type        = string
  default     = "9.37.0"
}
