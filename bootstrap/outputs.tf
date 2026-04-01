# =============================================================
# bootstrap/outputs.tf
# PURPOSE: Exposes the values you need AFTER running bootstrap
# WHAT TO DO: Copy these values and put them in the right places
#
# github_actions_role_arn → GitHub Secrets as AWS_ROLE_ARN
# state_bucket_name       → infrastructure/backend.tf bucket
# dynamodb_table_name     → infrastructure/backend.tf dynamodb_table
# =============================================================

output "state_bucket_name" {
  description = "COPY THIS → paste into infrastructure/backend.tf as the bucket value"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  description = "COPY THIS → paste into infrastructure/backend.tf as the dynamodb_table value"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "github_actions_role_arn" {
  description = "COPY THIS → add to GitHub repo Secrets as AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "github_oidc_provider_arn" {
  description = "For reference only — used internally by infrastructure/iam.tf"
  value       = aws_iam_openid_connect_provider.github.arn
}
