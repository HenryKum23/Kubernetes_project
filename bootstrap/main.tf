# =============================================================
# bootstrap/main.tf
# PURPOSE: Creates the foundation Terraform needs to operate
# WHEN:    Run once manually from your laptop before anything else
# STATE:   Stored LOCALLY in bootstrap/terraform.tfstate
# CREATES: S3 bucket, DynamoDB table, GitHub OIDC, IAM role
# =============================================================

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # LOCAL STATE — intentional
  # S3 does not exist yet so we cannot store state there
  # This is the only Terraform config in this project that uses local state
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# ── What this file creates ────────────────────────────────────

# 1. S3 bucket — stores all Terraform state for the main infrastructure
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. DynamoDB table — prevents two engineers running terraform apply at the same time
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  lifecycle { prevent_destroy = true }
}

# 3. GitHub OIDC provider — allows GitHub Actions to authenticate to AWS without keys
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# 4. GitHub Actions IAM role — the role your pipeline assumes via OIDC
resource "aws_iam_role" "github_actions" {
  name        = "${var.project_name}-github-actions-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*" }
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "${var.project_name}-github-actions-policy"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "EKS",         Effect = "Allow", Action = ["eks:*"],                  Resource = "*" },
      { Sid = "EC2",         Effect = "Allow", Action = ["ec2:*"],                  Resource = "*" },
      { Sid = "ECR",         Effect = "Allow", Action = ["ecr:*"],                  Resource = "*" },
      { Sid = "Logs",        Effect = "Allow", Action = ["logs:*"],                 Resource = "*" },
      { Sid = "ASG",         Effect = "Allow", Action = ["autoscaling:*"],          Resource = "*" },
      { Sid = "ELB",         Effect = "Allow", Action = ["elasticloadbalancing:*"], Resource = "*" },
      { Sid = "IAM",         Effect = "Allow", Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:AttachRolePolicy",
          "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:PassRole", "iam:TagRole",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
          "iam:GetPolicyVersion", "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider", "iam:TagOpenIDConnectProvider",
          "iam:CreateServiceLinkedRole"
        ], Resource = "*"
      },
      { Sid = "S3State", Effect = "Allow", Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      { Sid = "DynamoDB", Effect = "Allow", Action = [
          "dynamodb:GetItem", "dynamodb:PutItem",
          "dynamodb:DeleteItem", "dynamodb:DescribeTable"
        ],
        Resource = aws_dynamodb_table.terraform_locks.arn
      }
    ]
  })
}
