# Secure CI/CD Pipeline with Policy-as-Code Enforcement

A production-grade secure CI/CD pipeline with comprehensive security scanning, policy enforcement, and automated compliance checks.

##  Features

### Security Scanning
- **Secrets Scanning**: Detect leaked credentials and API keys
- **Container Scanning**: Vulnerability scanning with Trivy
- **IaC Scanning**: Terraform security checks with Checkov
- **Dependency Scanning**: Identify vulnerable dependencies
- **SBOM Generation**: Software Bill of Materials

### Policy Enforcement
- **OPA Integration**: Policy-as-code with Open Policy Agent
- **Container Policies**: Base image restrictions, root user prevention
- **Terraform Policies**: Encryption requirements, public access controls
- **Deployment Policies**: Approval workflows, deployment windows

### Pipeline Features
- **Multi-stage Pipeline**: Source → Scan → Build → Test → Deploy
- **Break-glass Deployments**: Emergency deployment process
- **Automated Rollback**: Quick rollback on failures
- **Audit Logging**: Complete audit trail in DynamoDB
- **Notifications**: Email and SNS alerts

##  Cost Estimate

**Monthly Cost**: ~$0-5 (within AWS Free Tier)

- CodeBuild: Free tier (100 minutes/month)
- CodePipeline: $1/active pipeline
- S3: <$1
- DynamoDB: Free tier
- ECR: Free tier (500 MB/month)
- SNS: <$1

##  Prerequisites

- AWS Account
- GitHub Account
- AWS CLI configured
- Terraform >= 1.0
- Docker
- Python 3.11+

##  Quick Start

### 1. Clone Repository
```bash
git clone <your-repo-url>
cd secure-cicd-pipeline
```

### 2. Configure Settings
```bash
# Edit Terraform variables
nano terraform/terraform.tfvars

# Update these values:
# - github_repo
# - notification_email
# - approval_sns_emails
```

### 3. Deploy Infrastructure
```bash
./scripts/deployment/deploy.sh
```

### 4. Configure GitHub Token
```bash
# Create GitHub Personal Access Token with scopes:
# - repo (full control)
# - admin:repo_hook

# Add to AWS Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id secure-cicd-github-token \
  --secret-string '{"token":"YOUR_GITHUB_PAT"}'
```

### 5. Confirm SNS Subscriptions

Check your email and confirm all SNS subscription links.

### 6. Test Pipeline
```bash
# Run local tests
./scripts/deployment/test-pipeline.sh

# Trigger pipeline by pushing code
git add .
git commit -m "Initial commit"
git push origin main
```

##  Architecture
```
┌─────────────┐
│   GitHub    │
│  Repository │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────┐
│        CodePipeline Stages          │
├─────────────────────────────────────┤
│ 1. Source (GitHub)                  │
│ 2. Security Scan                    │
│    - Secrets scanning               │
│    - IaC scanning (Checkov)         │
│    - Dockerfile scanning            │
│ 3. Unit Tests                       │
│ 4. Build Container                  │
│ 5. Container Scan (Trivy)           │
│ 6. Policy Check (OPA)               │
│ 7. Manual Approval                  │
│ 8. Deploy                           │
└─────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│         Security Gates              │
├─────────────────────────────────────┤
│ • No secrets in code                │
│ • No critical vulnerabilities       │
│ • IaC compliant                     │
│ • Policies enforced                 │
│ • Tests passing                     │
│ • Approval received                 │
└─────────────────────────────────────┘
```

##  Security Policies

### Container Policies
```rego
# Prohibited
- Using 'latest' tag
- Running as root user
- Exposed secrets
- Unapproved base images

# Required
- Specific version tags
- Non-root user
- Required labels
- No critical vulnerabilities
```

### Terraform Policies
```rego
# Required
- Encryption at rest
- Required tags (Environment, Owner, Project, CostCenter)
- No public access to sensitive resources
- KMS key rotation enabled

# Prohibited
- Public S3 buckets
- Unrestricted security groups (0.0.0.0/0 to SSH/RDP)
- Unencrypted EBS volumes
```

### Deployment Policies
```rego
# Production Deployments
- Manual approval required
- All tests must pass
- Security scans must pass
- Policy checks must pass
- Deployment window enforcement
- Break-glass option available
```

##  Viewing Results

### Pipeline Status
```bash
# View pipeline executions
aws codepipeline list-pipeline-executions \
  --pipeline-name secure-cicd-pipeline

# View specific execution
aws codepipeline get-pipeline-execution \
  --pipeline-name secure-cicd-pipeline \
  --pipeline-execution-id <execution-id>
```

### Security Reports
```bash
# List security scan reports
aws s3 ls s3://secure-cicd-scan-reports-XXXX/

# Download latest security scan
aws s3 cp s3://secure-cicd-scan-reports-XXXX/security-scans/ . --recursive

# View scan results in DynamoDB
aws dynamodb scan --table-name secure-cicd-scan-results
```

### Audit Logs
```bash
# View audit logs
aws dynamodb scan --table-name secure-cicd-audit-logs

# Query by event type
aws dynamodb query \
  --table-name secure-cicd-audit-logs \
  --index-name EventTypeIndex \
  --key-condition-expression "event_type = :type" \
  --expression-attribute-values '{":type":{"S":"policy_check"}}'
```

##  Testing Locally

### Run All Security Scans
```bash
# Secrets scan
./scripts/security/scan-secrets.sh

# IaC scan
./scripts/security/scan-iac.sh terraform

# Build and scan container
cd sample-app
docker build -t test-app:latest .
cd ..
./scripts/security/scan-container.sh test-app:latest
```

### Test OPA Policies
```bash
# Run policy tests
opa test policies/opa -v

# Evaluate specific policy
opa eval \
  --data policies/opa/container.rego \
  --data policies/opa/data.json \
  --input test-input.json \
  'data.container.allow'
```

### Run Unit Tests
```bash
cd sample-app
pip3 install -r requirements.txt
pip3 install pytest pytest-cov
pytest tests/ -v --cov=src
```

##  Break-Glass Deployment

For emergency deployments that bypass normal controls:

### 1. Create Break-Glass Request
```bash
cat > break-glass-request.json << EOL
{
  "environment": "production",
  "break_glass": {
    "enabled": true,
    "approved": true,
    "justification": "Critical security patch for CVE-2024-XXXX",
    "approver": "john.doe@example.com",
    "incident_ticket": "INC-12345"
  },
  "deployment_time": {
    "day": "$(date +%a)",
    "hour": $(date +%H)
  }
}
EOL
```

### 2. Validate with OPA
```bash
opa eval \
  --data policies/opa/deployment.rego \
  --input break-glass-request.json \
  'data.deployment.allow'
```

### 3. Deploy
```bash
# Override pipeline stage
aws codepipeline start-pipeline-execution \
  --name secure-cicd-pipeline
```

**Note**: All break-glass deployments are logged to audit table with 365-day retention.

##  Rollback Procedure

### Automatic Rollback

Pipeline automatically rolls back on:
- Failed tests
- Security scan failures (in strict mode)
- Policy violations
- Deployment failures

### Manual Rollback
```bash
# Rollback to previous version
./scripts/deployment/rollback.sh secure-cicd-pipeline

# Rollback to specific execution
./scripts/deployment/rollback.sh secure-cicd-pipeline <execution-id>
```

##  Monitoring & Alerts

### CloudWatch Dashboards
```bash
# View CodeBuild logs
aws logs tail /aws/codebuild/secure-cicd --follow

# View CodePipeline logs
aws logs tail /aws/codepipeline/secure-cicd --follow
```

### SNS Notifications

You'll receive notifications for:
- Pipeline execution status (started, succeeded, failed)
- Security scan failures
- Policy violations
- Approval requests
- Break-glass deployments

##  Customization

### Add Custom Security Checks

1. Create new buildspec in `buildspecs/`
2. Add CodeBuild project in `terraform/codebuild.tf`
3. Add stage to pipeline in `terraform/codepipeline.tf`

### Modify Policies
```bash
# Edit OPA policies
nano policies/opa/container.rego

# Test changes
opa test policies/opa -v

# Deploy
terraform apply
```

### Change Enforcement Mode
```hcl
# terraform.tfvars
policy_enforcement_mode = "strict"    # Blocks on violations
policy_enforcement_mode = "advisory"  # Warns but allows
policy_enforcement_mode = "permissive" # Logs only
```

##  Cleanup
```bash
# Navigate to terraform directory
cd terraform

# Empty S3 buckets
aws s3 rm s3://$(terraform output -raw artifacts_bucket) --recursive
aws s3 rm s3://$(terraform output -raw scan_reports_bucket) --recursive

# Destroy infrastructure
terraform destroy -auto-approve

# Clean local files
cd ..
rm -f deployment-outputs.json
rm -rf terraform/.terraform
rm -f terraform/tfplan
rm -rf sample-app/__pycache__
rm -rf sample-app/tests/__pycache__
```

##  Sample Reports

### Security Scan Report
```json
{
  "scan_id": "scan-1234567890",
  "timestamp": "2024-02-19T10:30:00Z",
  "results": {
    "secrets_scan": "PASS",
    "iac_scan": "PASS",
    "dockerfile_scan": "PASS"
  },
  "vulnerabilities": {
    "critical": 0,
    "high": 0,
    "medium": 2
  }
}
```

### Policy Evaluation Report
```json
{
  "allow": true,
  "violations": [],
  "recommendations": [
    "Consider enabling enhanced monitoring for production"
  ]
}
```

##  Contributing

This is a reference implementation. Feel free to:
- Fork and customize
- Add additional security checks
- Extend policies
- Improve documentation

##  License

MIT License

##  Learning Resources

- [AWS CodePipeline Documentation](https://docs.aws.amazon.com/codepipeline/)
- [Open Policy Agent Documentation](https://www.openpolicyagent.org/docs/)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [Checkov Documentation](https://www.checkov.io/1.Welcome/What%20is%20Checkov.html)
- [OWASP DevSecOps Guidelines](https://owasp.org/www-project-devsecops-guideline/)

