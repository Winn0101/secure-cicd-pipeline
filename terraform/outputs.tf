output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "pipeline_name" {
  description = "CodePipeline name"
  value       = aws_codepipeline.main.name
}

output "artifacts_bucket" {
  description = "S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.id
}

output "scan_reports_bucket" {
  description = "S3 bucket for security scan reports"
  value       = aws_s3_bucket.scan_reports.id
}

output "dynamodb_tables" {
  description = "DynamoDB table names"
  value = {
    pipeline_state = aws_dynamodb_table.pipeline_state.name
    scan_results   = aws_dynamodb_table.scan_results.name
    audit_logs     = aws_dynamodb_table.audit_logs.name
  }
}

output "sns_topics" {
  description = "SNS topic ARNs"
  value = {
    pipeline_notifications = aws_sns_topic.pipeline_notifications.arn
    approval_requests      = aws_sns_topic.approval_requests.arn
    security_alerts        = aws_sns_topic.security_alerts.arn
  }
}

output "codebuild_projects" {
  description = "CodeBuild project names"
  value = {
    security_scan  = aws_codebuild_project.security_scan.name
    container_build = aws_codebuild_project.container_build.name
    container_scan = aws_codebuild_project.container_scan.name
    policy_check   = aws_codebuild_project.policy_check.name
    unit_tests     = aws_codebuild_project.unit_tests.name
  }
}

output "useful_commands" {
  description = "Useful commands"
  value = <<-EOT
    # View pipeline executions
    aws codepipeline list-pipeline-executions --pipeline-name ${aws_codepipeline.main.name}
    
    # View CodeBuild builds
    aws codebuild list-builds-for-project --project-name ${aws_codebuild_project.security_scan.name}
    
    # View scan results
    aws dynamodb scan --table-name ${aws_dynamodb_table.scan_results.name}
    
    # View security reports in S3
    aws s3 ls s3://${aws_s3_bucket.scan_reports.id}/
    
    # View audit logs
    aws dynamodb scan --table-name ${aws_dynamodb_table.audit_logs.name}
    
    # Push image to ECR
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}
    docker build -t ${aws_ecr_repository.app.repository_url}:latest sample-app/
    docker push ${aws_ecr_repository.app.repository_url}:latest
    
    # View CodeBuild logs
    aws logs tail /aws/codebuild/${var.project_name} --follow
  EOT
}

output "deployment_info" {
  description = "Deployment information"
  value = <<-EOT
    Secure CI/CD Pipeline Deployed Successfully!
    
       Container Registry:
       ECR: ${aws_ecr_repository.app.repository_url}
    
       Pipeline:
       Name: ${aws_codepipeline.main.name}
       Console: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.main.name}/view
    
       Reports:
       S3 Bucket: ${aws_s3_bucket.scan_reports.id}
       Path: s3://${aws_s3_bucket.scan_reports.id}/
    
       Notifications:
       - Pipeline updates: ${var.notification_email}
       - Approvals: ${join(", ", var.approval_sns_emails)}
       - Security alerts: ${var.notification_email}
    
       Security Features:
       - Secrets scanning: ✓
       - Container scanning: ✓
       - IaC scanning: ✓
       - Policy enforcement: ${var.policy_enforcement_mode}
       - Break-glass: ${var.enable_break_glass ? "Enabled" : "Disabled"}
    
    ⚠️  NEXT STEPS:
    1. Confirm SNS subscriptions in email
    2. Add GitHub token to Secrets Manager:
       aws secretsmanager put-secret-value \
         --secret-id ${aws_secretsmanager_secret.github_token.name} \
         --secret-string '{"token":"YOUR_GITHUB_PAT"}'
    3. Test pipeline:
       Push code to GitHub ${var.github_repo}
    4. Review security reports in S3
  EOT
}
