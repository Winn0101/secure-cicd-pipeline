#!/bin/bash

set -e

echo "🗑️  Tearing Down Secure CI/CD Pipeline..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Navigate to project root
cd "$(dirname "$0")/../../"

# Confirmation
echo -e "${RED}⚠️  WARNING: This will destroy all infrastructure!${NC}"
echo ""
echo -e "${YELLOW}This will delete:${NC}"
echo "  • CodePipeline and all executions"
echo "  • CodeBuild projects and build history"
echo "  • ECR repository and all container images"
echo "  • S3 buckets (artifacts and scan reports)"
echo "  • DynamoDB tables (pipeline state, scan results, audit logs)"
echo "  • SNS topics and subscriptions"
echo "  • Secrets Manager secrets"
echo "  • KMS keys"
echo "  • IAM roles and policies"
echo "  • CloudWatch log groups"
echo ""
read -p "Are you absolutely sure? Type 'destroy' to confirm: " confirm

if [ "$confirm" != "destroy" ]; then
    echo -e "${GREEN}Teardown cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting teardown process...${NC}"

# Check if Terraform is available
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Terraform not found. Please install Terraform first.${NC}"
    exit 1
fi

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI not found. Please install AWS CLI first.${NC}"
    exit 1
fi

# Navigate to terraform directory
cd terraform

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
    echo -e "${YELLOW}No Terraform state found. Checking for remote resources...${NC}"
fi

# Step 1: Stop any running pipeline executions
echo -e "${BLUE}Step 1: Stopping active pipeline executions...${NC}"

PIPELINE_NAME=$(terraform output -raw pipeline_name 2>/dev/null || echo "")

if [ -n "$PIPELINE_NAME" ]; then
    echo "Pipeline: $PIPELINE_NAME"
    
    # Get active executions
    ACTIVE_EXECUTIONS=$(aws codepipeline list-pipeline-executions \
        --pipeline-name "$PIPELINE_NAME" \
        --query 'pipelineExecutionSummaries[?status==`InProgress`].pipelineExecutionId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ACTIVE_EXECUTIONS" ]; then
        for execution_id in $ACTIVE_EXECUTIONS; do
            echo "  Stopping execution: $execution_id"
            aws codepipeline stop-pipeline-execution \
                --pipeline-name "$PIPELINE_NAME" \
                --pipeline-execution-id "$execution_id" \
                --abandon \
                --reason "Infrastructure teardown" 2>/dev/null || true
        done
        echo -e "${GREEN}✓ Stopped active executions${NC}"
    else
        echo "  No active executions found"
    fi
else
    echo "  No pipeline found"
fi

echo ""

# Step 2: Delete ECR images
echo -e "${BLUE}Step 2: Deleting ECR repository images...${NC}"

ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")

if [ -n "$ECR_REPO" ]; then
    REPO_NAME=$(echo $ECR_REPO | rev | cut -d'/' -f1 | rev)
    echo "Repository: $REPO_NAME"
    
    # List and delete all images
    IMAGE_IDS=$(aws ecr list-images \
        --repository-name "$REPO_NAME" \
        --query 'imageIds[*]' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$IMAGE_IDS" != "[]" ] && [ -n "$IMAGE_IDS" ]; then
        echo "  Deleting images..."
        aws ecr batch-delete-image \
            --repository-name "$REPO_NAME" \
            --image-ids "$IMAGE_IDS" 2>/dev/null || true
        echo -e "${GREEN}✓ Deleted ECR images${NC}"
    else
        echo "  No images found"
    fi
else
    echo "  No ECR repository found"
fi

echo ""

# Step 3: Empty S3 buckets
echo -e "${BLUE}Step 3: Emptying S3 buckets...${NC}"

ARTIFACTS_BUCKET=$(terraform output -raw artifacts_bucket 2>/dev/null || echo "")
REPORTS_BUCKET=$(terraform output -raw scan_reports_bucket 2>/dev/null || echo "")

# Empty artifacts bucket
if [ -n "$ARTIFACTS_BUCKET" ]; then
    echo "Emptying: $ARTIFACTS_BUCKET"
    aws s3 rm "s3://$ARTIFACTS_BUCKET" --recursive 2>/dev/null || true
    echo -e "${GREEN}✓ Emptied artifacts bucket${NC}"
else
    echo "  No artifacts bucket found"
fi

# Empty reports bucket
if [ -n "$REPORTS_BUCKET" ]; then
    echo "Emptying: $REPORTS_BUCKET"
    aws s3 rm "s3://$REPORTS_BUCKET" --recursive 2>/dev/null || true
    echo -e "${GREEN}✓ Emptied reports bucket${NC}"
else
    echo "  No reports bucket found"
fi

echo ""

# Step 4: Backup important data (optional)
echo -e "${BLUE}Step 4: Creating backup of important data...${NC}"

BACKUP_DIR="../backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup DynamoDB tables
TABLES=$(terraform output -json dynamodb_tables 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")

if [ -n "$TABLES" ]; then
    for table in $TABLES; do
        echo "  Backing up table: $table"
        aws dynamodb scan --table-name "$table" --output json > "$BACKUP_DIR/$table.json" 2>/dev/null || true
    done
    echo -e "${GREEN}✓ Backed up DynamoDB tables to $BACKUP_DIR${NC}"
else
    echo "  No tables to backup"
fi

# Backup Terraform state
if [ -f "terraform.tfstate" ]; then
    cp terraform.tfstate "$BACKUP_DIR/terraform.tfstate.backup"
    echo -e "${GREEN}✓ Backed up Terraform state${NC}"
fi

echo ""

# Step 5: Destroy Terraform infrastructure
echo -e "${BLUE}Step 5: Destroying Terraform infrastructure...${NC}"

# Initialize if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Destroy
echo "Running terraform destroy..."
terraform destroy -auto-approve

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Infrastructure destroyed${NC}"
else
    echo -e "${RED}✗ Terraform destroy encountered errors${NC}"
    echo -e "${YELLOW}Attempting manual cleanup of remaining resources...${NC}"
fi

echo ""

# Step 6: Manual cleanup of any remaining resources
echo -e "${BLUE}Step 6: Checking for remaining resources...${NC}"

# Check for orphaned CodeBuild projects
echo "  Checking CodeBuild projects..."
ORPHANED_BUILDS=$(aws codebuild list-projects --query 'projects[?contains(@, `secure-cicd`) == `true`]' --output text 2>/dev/null || echo "")

if [ -n "$ORPHANED_BUILDS" ]; then
    for project in $ORPHANED_BUILDS; do
        echo "    Deleting: $project"
        aws codebuild delete-project --name "$project" 2>/dev/null || true
    done
fi

# Check for orphaned SNS topics
echo "  Checking SNS topics..."
ORPHANED_TOPICS=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `secure-cicd`) == `true`].TopicArn' --output text 2>/dev/null || echo "")

if [ -n "$ORPHANED_TOPICS" ]; then
    for topic in $ORPHANED_TOPICS; do
        echo "    Deleting: $topic"
        aws sns delete-topic --topic-arn "$topic" 2>/dev/null || true
    done
fi

# Check for orphaned Secrets
echo "  Checking Secrets Manager..."
ORPHANED_SECRETS=$(aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `secure-cicd`) == `true`].Name' --output text 2>/dev/null || echo "")

if [ -n "$ORPHANED_SECRETS" ]; then
    for secret in $ORPHANED_SECRETS; do
        echo "    Deleting: $secret"
        aws secretsmanager delete-secret --secret-id "$secret" --force-delete-without-recovery 2>/dev/null || true
    done
fi

echo -e "${GREEN}✓ Cleanup check complete${NC}"

echo ""

# Step 7: Clean local files
echo -e "${BLUE}Step 7: Cleaning local files...${NC}"

cd ..

# Remove Terraform files
rm -f terraform/.terraform.lock.hcl
rm -rf terraform/.terraform
rm -f terraform/tfplan
rm -f terraform/*.tfstate*
rm -f deployment-outputs.json

# Remove reports
rm -rf reports/

# Remove Python cache
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true

# Remove virtual environments
rm -rf sample-app/venv 2>/dev/null || true

# Remove Docker images (optional)
read -p "Remove local Docker images? (yes/no): " remove_docker

if [ "$remove_docker" = "yes" ]; then
    echo "  Removing Docker images..."
    docker images | grep "secure-cicd\|test" | awk '{print $3}' | xargs docker rmi -f 2>/dev/null || true
    echo -e "${GREEN}✓ Removed Docker images${NC}"
fi

echo -e "${GREEN}✓ Local files cleaned${NC}"

echo ""

# Summary
echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}Teardown Complete!${NC}"
echo -e "${GREEN}==================================${NC}"
echo ""
echo "Removed resources:"
echo "  ✓ CodePipeline and executions"
echo "  ✓ CodeBuild projects"
echo "  ✓ ECR repository and images"
echo "  ✓ S3 buckets (emptied and deleted)"
echo "  ✓ DynamoDB tables"
echo "  ✓ SNS topics"
echo "  ✓ Secrets Manager secrets"
echo "  ✓ KMS keys"
echo "  ✓ IAM roles and policies"
echo "  ✓ CloudWatch log groups"
echo ""
echo -e "${BLUE}Backup location:${NC} $BACKUP_DIR"
echo ""
echo -e "${YELLOW}Note: Some resources may take time to fully delete:${NC}"
echo "  • KMS keys: 7-30 day deletion window"
echo "  • Secrets: May have recovery window"
echo "  • CloudWatch logs: May persist briefly"
echo ""
echo -e "${GREEN}You can now safely remove the project directory${NC}"
