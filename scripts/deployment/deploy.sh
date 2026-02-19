#!/bin/bash

set -e

echo "Deploying Secure CI/CD Pipeline..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI not found${NC}"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Terraform not found${NC}"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"

# Verify AWS credentials
echo -e "${YELLOW}Verifying AWS credentials...${NC}"
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}AWS credentials not configured${NC}"
    exit 1
fi

echo -e "${GREEN}✓ AWS credentials verified${NC}"

# Navigate to terraform directory
cd "$(dirname "$0")/../../terraform"

# Check terraform.tfvars
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}terraform.tfvars not found!${NC}"
    exit 1
fi

if grep -q "your-username/your-repo" terraform.tfvars; then
    echo -e "${RED}Please update github_repo in terraform.tfvars${NC}"
    exit 1
fi

if grep -q "your-email@example.com" terraform.tfvars; then
    echo -e "${RED}Please update email addresses in terraform.tfvars${NC}"
    exit 1
fi

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Validate
echo -e "${YELLOW}Validating configuration...${NC}"
terraform validate
if [ $? -ne 0 ]; then
    echo -e "${RED}Validation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Validation passed${NC}"

# Plan
echo -e "${YELLOW}Creating deployment plan...${NC}"
terraform plan -out=tfplan

# Confirm
echo -e "${YELLOW}Ready to deploy Secure CI/CD Pipeline${NC}"
echo -e "${BLUE}This will create:${NC}"
echo "  • 1 ECR repository"
echo "  • 5 CodeBuild projects"
echo "  • 1 CodePipeline"
echo "  • 2 S3 buckets"
echo "  • 3 DynamoDB tables"
echo "  • 3 SNS topics"
echo "  • 2 Secrets Manager secrets"
echo "  • 1 KMS key"
echo "  • Multiple IAM roles"
echo ""
read -p "Proceed with deployment? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${RED}Deployment cancelled${NC}"
    exit 0
fi

# Deploy
echo -e "${YELLOW}Deploying infrastructure...${NC}"
terraform apply tfplan

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deployment completed successfully!${NC}"
    
    # Save outputs
    terraform output -json > ../deployment-outputs.json
    
    # Display info
    echo -e "${GREEN}==================================${NC}"
    terraform output deployment_info
    echo -e "${GREEN}==================================${NC}"
    
    # Get GitHub token
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANT: Add GitHub Personal Access Token${NC}"
    echo "1. Create a GitHub PAT with 'repo' and 'admin:repo_hook' scopes"
    echo "2. Run this command:"
    echo ""
    SECRET_NAME=$(terraform output -json | jq -r '.useful_commands.value' | grep 'secret-id' | awk '{print $3}')
    echo -e "${BLUE}aws secretsmanager put-secret-value \\${NC}"
    echo -e "${BLUE}  --secret-id $SECRET_NAME \\${NC}"
    echo -e "${BLUE}  --secret-string '{\"token\":\"YOUR_GITHUB_PAT\"}'${NC}"
    
else
    echo -e "${RED} Deployment failed${NC}"
    exit 1
fi
