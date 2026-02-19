# CodePipeline
resource "aws_codepipeline" "main" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner      = split("/", var.github_repo)[0]
        Repo       = split("/", var.github_repo)[1]
        Branch     = var.github_branch
        OAuthToken = "{{resolve:secretsmanager:${aws_secretsmanager_secret.github_token.name}:SecretString:token}}"
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
        CustomData      = "Please review security scan results and approve deployment to production"
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
        ProjectName = aws_codebuild_project.container_build.name
        EnvironmentVariablesOverride = jsonencode([
          {
            name  = "DEPLOYMENT_STAGE"
            value = "production"
            type  = "PLAINTEXT"
          }
        ])
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
  description = "Trigger pipeline on GitHub push"

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
}
