# CodeBuild Project for Security Scanning
resource "aws_codebuild_project" "security_scan" {
  name          = "${var.project_name}-security-scan"
  description   = "Security scanning stage"
  build_timeout = 30
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "SCAN_REPORTS_BUCKET"
      value = aws_s3_bucket.scan_reports.id
    }

    environment_variable {
      name  = "SECURITY_ALERTS_TOPIC"
      value = aws_sns_topic.security_alerts.arn
    }

    environment_variable {
      name  = "SCAN_RESULTS_TABLE"
      value = aws_dynamodb_table.scan_results.name
    }

    environment_variable {
      name  = "FAIL_ON_HIGH"
      value = var.security_scan_fail_on_high
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "security-scan"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/../buildspecs/security-scan.yml")
  }

  tags = {
    Name = "${var.project_name}-security-scan"
  }
}

# CodeBuild Project for Container Build
resource "aws_codebuild_project" "container_build" {
  name          = "${var.project_name}-container-build"
  description   = "Build and push container image"
  build_timeout = 30
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.app.repository_url
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = var.container_image_tag
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "container-build"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/../buildspecs/container-build.yml")
  }

  tags = {
    Name = "${var.project_name}-container-build"
  }
}

# CodeBuild Project for Container Scanning
resource "aws_codebuild_project" "container_scan" {
  name          = "${var.project_name}-container-scan"
  description   = "Scan container image for vulnerabilities"
  build_timeout = 20
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.app.repository_url
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = var.container_image_tag
    }

    environment_variable {
      name  = "SCAN_REPORTS_BUCKET"
      value = aws_s3_bucket.scan_reports.id
    }

    environment_variable {
      name  = "SCAN_RESULTS_TABLE"
      value = aws_dynamodb_table.scan_results.name
    }

    environment_variable {
      name  = "FAIL_ON_HIGH"
      value = var.security_scan_fail_on_high
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "container-scan"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/../buildspecs/container-scan.yml")
  }

  tags = {
    Name = "${var.project_name}-container-scan"
  }
}

# CodeBuild Project for Policy Check
resource "aws_codebuild_project" "policy_check" {
  name          = "${var.project_name}-policy-check"
  description   = "OPA policy validation"
  build_timeout = 15
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "POLICY_ENFORCEMENT_MODE"
      value = var.policy_enforcement_mode
    }

    environment_variable {
      name  = "SCAN_REPORTS_BUCKET"
      value = aws_s3_bucket.scan_reports.id
    }

    environment_variable {
      name  = "AUDIT_LOGS_TABLE"
      value = aws_dynamodb_table.audit_logs.name
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "policy-check"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/../buildspecs/policy-check.yml")
  }

  tags = {
    Name = "${var.project_name}-policy-check"
  }
}

# CodeBuild Project for Unit Tests
resource "aws_codebuild_project" "unit_tests" {
  name          = "${var.project_name}-unit-tests"
  description   = "Run unit tests"
  build_timeout = 15
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "ENVIRONMENT"
      value = var.environment
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "unit-tests"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/../buildspecs/unit-tests.yml")
  }

  tags = {
    Name = "${var.project_name}-unit-tests"
  }
}
