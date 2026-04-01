# =============================================================
# bootstrap/variables.tf
# PURPOSE: Inputs for the bootstrap layer only
# NOTICE:  These variables are about WHO is running the project
#          and WHERE to put the foundation resources
#          They are NOT about the application or cluster itself
# =============================================================

variable "aws_region" {
  description = "AWS region where bootstrap resources will be created"
  type        = string
  default     = "us-east-1"
  # This should match the region in infrastructure/variables.tf
}

variable "project_name" {
  description = "Prefix for all bootstrap resource names e.g. henry-eks"
  type        = string
  default     = "henry-eks"
  # Used to name: S3 bucket, DynamoDB table, IAM role
}

variable "github_repository" {
  description = "Your GitHub repo in format owner/repo — scopes OIDC trust to your repo only"
  type        = string
  default     = "HenryKum23/Kubernetes_project"
  # IMPORTANT: Change this if you fork or rename the repo
  # If this is wrong, the pipeline cannot assume the AWS role
}
