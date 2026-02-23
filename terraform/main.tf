# Random suffix for unique names
resource "random_id" "suffix" {
  byte_length = 4
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# S3 Bucket for Pipeline Artifacts
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = "${var.project_name}-artifacts-${random_id.suffix.hex}"

  tags = {
    Name = "${var.project_name}-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket for Security Scan Reports
resource "aws_s3_bucket" "scan_reports" {
  bucket = "${var.project_name}-scan-reports-${random_id.suffix.hex}"

  tags = {
    Name = "${var.project_name}-scan-reports"
  }
}

resource "aws_s3_bucket_versioning" "scan_reports" {
  bucket = aws_s3_bucket.scan_reports.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scan_reports" {
  bucket = aws_s3_bucket.scan_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "scan_reports" {
  bucket = aws_s3_bucket.scan_reports.id

  rule {
    id     = "delete-old-reports"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }
  }
}

# ECR Repository for Container Images
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-app-repo"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# DynamoDB Table for Pipeline State
resource "aws_dynamodb_table" "pipeline_state" {
  name           = "${var.project_name}-pipeline-state"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "pipeline_id"
  range_key      = "execution_id"

  attribute {
    name = "pipeline_id"
    type = "S"
  }

  attribute {
    name = "execution_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    range_key       = "execution_id"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-pipeline-state"
  }
}

# DynamoDB Table for Security Scan Results
resource "aws_dynamodb_table" "scan_results" {
  name           = "${var.project_name}-scan-results"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "scan_id"
  range_key      = "timestamp"

  attribute {
    name = "scan_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "scan_type"
    type = "S"
  }

  global_secondary_index {
    name            = "ScanTypeIndex"
    hash_key        = "scan_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-scan-results"
  }
}

# DynamoDB Table for Audit Logs
resource "aws_dynamodb_table" "audit_logs" {
  name           = "${var.project_name}-audit-logs"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "event_id"
  range_key      = "timestamp"

  attribute {
    name = "event_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "event_type"
    type = "S"
  }

  global_secondary_index {
    name            = "EventTypeIndex"
    hash_key        = "event_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-audit-logs"
  }
}

# KMS Key for Secrets
resource "aws_kms_key" "secrets" {
  description             = "KMS key for ${var.project_name} secrets"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-secrets-key"
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Secrets Manager - GitHub Token (placeholder)
resource "aws_secretsmanager_secret" "github_token" {
  name                    = "${var.project_name}-github-token"
  description             = "GitHub personal access token for CI/CD"
  kms_key_id              = aws_kms_key.secrets.id
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-github-token"
  }
}

# Secrets Manager - Container Registry Credentials
resource "aws_secretsmanager_secret" "ecr_credentials" {
  name                    = "${var.project_name}-ecr-credentials"
  description             = "ECR credentials for container scanning"
  kms_key_id              = aws_kms_key.secrets.id
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-ecr-credentials"
  }
}

# SNS Topic for Pipeline Notifications
resource "aws_sns_topic" "pipeline_notifications" {
  name              = "${var.project_name}-pipeline-notifications"
  kms_master_key_id = aws_kms_key.secrets.id

  tags = {
    Name = "${var.project_name}-pipeline-notifications"
  }
}

resource "aws_sns_topic_subscription" "pipeline_email" {
  topic_arn = aws_sns_topic.pipeline_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS Topic for Approval Requests
resource "aws_sns_topic" "approval_requests" {
  name              = "${var.project_name}-approval-requests"
  kms_master_key_id = aws_kms_key.secrets.id

  tags = {
    Name = "${var.project_name}-approval-requests"
  }
}

resource "aws_sns_topic_subscription" "approval_emails" {
  count     = length(var.approval_sns_emails)
  topic_arn = aws_sns_topic.approval_requests.arn
  protocol  = "email"
  endpoint  = var.approval_sns_emails[count.index]
}

# SNS Topic for Security Alerts
resource "aws_sns_topic" "security_alerts" {
  name              = "${var.project_name}-security-alerts"
  kms_master_key_id = aws_kms_key.secrets.id

  tags = {
    Name = "${var.project_name}-security-alerts"
  }
}

resource "aws_sns_topic_subscription" "security_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Log Group for CodeBuild
resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-codebuild-logs"
  }
}

# CloudWatch Log Group for CodePipeline
resource "aws_cloudwatch_log_group" "codepipeline" {
  name              = "/aws/codepipeline/${var.project_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-codepipeline-logs"
  }
}

# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name_prefix = "${var.project_name}-codebuild-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-codebuild-role"
  }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name_prefix = "${var.project_name}-codebuild-"
  role        = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*",
          aws_s3_bucket.scan_reports.arn,
          "${aws_s3_bucket.scan_reports.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.github_token.arn,
          aws_secretsmanager_secret.ecr_credentials.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.secrets.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.scan_results.arn,
          aws_dynamodb_table.pipeline_state.arn,
          aws_dynamodb_table.audit_logs.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.pipeline_notifications.arn,
          aws_sns_topic.security_alerts.arn
        ]
      }
    ]
  })
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name_prefix = "${var.project_name}-codepipeline-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-codepipeline-role"
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name_prefix = "${var.project_name}-codepipeline-"
  role        = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.pipeline_notifications.arn,
          aws_sns_topic.approval_requests.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.pipeline_state.arn,
          aws_dynamodb_table.audit_logs.arn
        ]
      }
    ]
  })
}
# Additional IAM permissions for CodeStar Connections
resource "aws_iam_role_policy" "codepipeline_codestar" {
  name_prefix = "${var.project_name}-codestar-"
  role        = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection"
        ]
        Resource = aws_codestarconnections_connection.github.arn
      }
    ]
  })
}
