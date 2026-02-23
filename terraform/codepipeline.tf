# CodeStar Connection for GitHub (v2)
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project_name}-github"
  provider_type = "GitHub"

  tags = {
    Name = "${var.project_name}-github-connection"
  }
}

# CodeBuild Project for Deployment
resource "aws_codebuild_project" "deploy" {
  name          = "${var.project_name}-deploy"
  description   = "Deploy application to production"
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
      name  = "DEPLOYMENT_STAGE"
      value = "production"
    }

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
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "deploy"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/../buildspecs/deploy.yml")
  }

  tags = {
    Name = "${var.project_name}-deploy"
  }
}

# CodePipeline - WITHOUT KMS encryption on artifact store
resource "aws_codepipeline" "main" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
    # Removed encryption_key to use S3 default encryption
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.github_repo
        BranchName           = var.github_branch
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "SecurityScan"

    action {
      name             = "SecurityScan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["security_scan_output"]

      configuration = {
        ProjectName = aws_codebuild_project.security_scan.name
      }
    }
  }

  stage {
    name = "UnitTests"

    action {
      name             = "RunTests"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["test_output"]

      configuration = {
        ProjectName = aws_codebuild_project.unit_tests.name
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildContainer"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.container_build.name
      }
    }
  }

  stage {
    name = "ContainerScan"

    action {
      name             = "ScanContainer"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["container_scan_output"]

      configuration = {
        ProjectName = aws_codebuild_project.container_scan.name
      }
    }
  }

  stage {
    name = "PolicyCheck"

    action {
      name             = "PolicyValidation"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["policy_check_output"]

      configuration = {
        ProjectName = aws_codebuild_project.policy_check.name
      }
    }
  }

  stage {
    name = "ApprovalForProduction"

    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = aws_sns_topic.approval_requests.arn
        CustomData      = "Please review security scan results before approving deployment to production. Check the scan reports in S3 and verify all tests passed."
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployToProduction"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.deploy.name
      }
    }
  }

  tags = {
    Name = "${var.project_name}-pipeline"
  }
}

# EventBridge Rule to trigger pipeline on code changes
resource "aws_cloudwatch_event_rule" "pipeline_trigger" {
  name        = "${var.project_name}-pipeline-trigger"
  description = "Trigger pipeline on execution state changes"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      pipeline = [aws_codepipeline.main.name]
      state    = ["STARTED", "SUCCEEDED", "FAILED"]
    }
  })

  tags = {
    Name = "${var.project_name}-pipeline-trigger"
  }
}

resource "aws_cloudwatch_event_target" "pipeline_notification" {
  rule      = aws_cloudwatch_event_rule.pipeline_trigger.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.pipeline_notifications.arn

  input_transformer {
    input_paths = {
      pipeline  = "$.detail.pipeline"
      state     = "$.detail.state"
      execution = "$.detail.execution-id"
    }
    input_template = <<EOF
{
  "pipeline": "<pipeline>",
  "state": "<state>",
  "execution_id": "<execution>",
  "message": "Pipeline <pipeline> is now in <state> state. Execution ID: <execution>"
}
EOF
  }
}

# SNS Topic Policy to allow EventBridge
resource "aws_sns_topic_policy" "pipeline_notifications" {
  arn = aws_sns_topic.pipeline_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.pipeline_notifications.arn
      }
    ]
  })
}
