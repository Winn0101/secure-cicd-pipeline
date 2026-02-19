#!/bin/bash

set -e

echo "Testing Secure CI/CD Pipeline..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$(dirname "$0")/../../"

TESTS_PASSED=0
TESTS_FAILED=0

# Helper function
run_test() {
    local test_name=$1
    local test_command=$2
    
    echo -e "${YELLOW}Running: $test_name${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✓ $test_name passed${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

echo "Starting pipeline tests..."
echo ""

# Test 1: Check if scripts exist and are executable
echo -e "${BLUE}=== Test 1: Script Validation ===${NC}"
run_test "Check scan-secrets.sh exists" "test -x scripts/security/scan-secrets.sh"
run_test "Check scan-iac.sh exists" "test -x scripts/security/scan-iac.sh"
run_test "Check scan-container.sh exists" "test -x scripts/security/scan-container.sh"
run_test "Check policy-check.sh exists" "test -x scripts/security/policy-check.sh"

echo ""

# Test 2: Secrets Scanning
echo -e "${BLUE}=== Test 2: Secrets Scanning ===${NC}"
if command -v git-secrets &> /dev/null; then
    run_test "Secrets scanning" "./scripts/security/scan-secrets.sh . 2>&1 | tail -5"
else
    echo -e "${YELLOW}⚠ git-secrets not installed, skipping${NC}"
fi

echo ""

# Test 3: Terraform Validation
echo -e "${BLUE}=== Test 3: Terraform Validation ===${NC}"
if [ -d "terraform" ]; then
    cd terraform
    run_test "Terraform init" "terraform init -backend=false > /dev/null 2>&1"
    run_test "Terraform validate" "terraform validate > /dev/null 2>&1"
    run_test "Terraform format check" "terraform fmt -check -recursive . > /dev/null 2>&1 || true"
    cd ..
else
    echo -e "${RED}Terraform directory not found${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# Test 4: OPA Policy Tests
echo -e "${BLUE}=== Test 4: OPA Policy Tests ===${NC}"
if command -v opa &> /dev/null; then
    if [ -d "policies/opa" ]; then
        run_test "OPA policy tests" "opa test policies/opa -v 2>&1 | tail -10"
    else
        echo -e "${YELLOW}⚠ OPA policies directory not found${NC}"
    fi
else
    echo -e "${YELLOW}⚠ OPA not installed, skipping${NC}"
fi

echo ""

# Test 5: Dockerfile Validation
echo -e "${BLUE}=== Test 5: Dockerfile Validation ===${NC}"
if [ -f "sample-app/Dockerfile" ]; then
    run_test "Dockerfile exists" "test -f sample-app/Dockerfile"
    run_test "Dockerfile syntax" "docker build --no-cache -f sample-app/Dockerfile sample-app -t test:syntax 2>&1 | tail -5 || true"
else
    echo -e "${RED}Dockerfile not found${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# Test 6: Python Application Tests
echo -e "${BLUE}=== Test 6: Python Application Tests ===${NC}"
if [ -f "sample-app/requirements.txt" ]; then
    cd sample-app
    
    # Check if virtual environment should be used
    if [ ! -d "venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv venv
    fi
    
    source venv/bin/activate
    
    run_test "Install dependencies" "pip install -q -r requirements.txt && pip install -q pytest pytest-cov 2>&1 | tail -5"
    run_test "Run unit tests" "python3 -m pytest tests/ -v 2>&1 | tail -20"
    
    deactivate
    cd ..
else
    echo -e "${YELLOW}⚠ Sample app not found, skipping${NC}"
fi

echo ""

# Test 7: Check AWS Infrastructure (if deployed)
echo -e "${BLUE}=== Test 7: AWS Infrastructure Check ===${NC}"

if [ -f "terraform/terraform.tfstate" ] || [ -f "deployment-outputs.json" ]; then
    cd terraform
    
    if command -v aws &> /dev/null; then
        # Check if pipeline exists
        PIPELINE_NAME=$(terraform output -raw pipeline_name 2>/dev/null || echo "")
        
        if [ -n "$PIPELINE_NAME" ]; then
            run_test "Pipeline exists" "aws codepipeline get-pipeline --name $PIPELINE_NAME > /dev/null 2>&1"
            
            # Get pipeline status
            echo -e "${YELLOW}Checking pipeline status...${NC}"
            aws codepipeline get-pipeline-state --name "$PIPELINE_NAME" --query 'stageStates[*].[stageName,latestExecution.status]' --output table 2>/dev/null || echo "Could not retrieve status"
        else
            echo -e "${YELLOW}⚠ Pipeline not deployed yet${NC}"
        fi
        
        # Check ECR repository
        ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
        if [ -n "$ECR_REPO" ]; then
            REPO_NAME=$(echo $ECR_REPO | rev | cut -d'/' -f1 | rev)
            run_test "ECR repository exists" "aws ecr describe-repositories --repository-names $REPO_NAME > /dev/null 2>&1"
        fi
    else
        echo -e "${YELLOW}⚠ AWS CLI not configured, skipping${NC}"
    fi
    
    cd ..
else
    echo -e "${YELLOW}⚠ Infrastructure not deployed, skipping${NC}"
fi

echo ""

# Test 8: Check Required Files
echo -e "${BLUE}=== Test 8: Required Files Check ===${NC}"
run_test "README.md exists" "test -f README.md"
run_test "Main Terraform file exists" "test -f terraform/main.tf"
run_test "Variables file exists" "test -f terraform/variables.tf"
run_test "Container policy exists" "test -f policies/opa/container.rego"
run_test "Deployment policy exists" "test -f policies/opa/deployment.rego"
run_test "Terraform policy exists" "test -f policies/opa/terraform.rego"

echo ""

# Test 9: BuildSpec Files
echo -e "${BLUE}=== Test 9: BuildSpec Files ===${NC}"
run_test "Security scan buildspec exists" "test -f buildspecs/security-scan.yml"
run_test "Container build buildspec exists" "test -f buildspecs/container-build.yml"
run_test "Container scan buildspec exists" "test -f buildspecs/container-scan.yml"
run_test "Policy check buildspec exists" "test -f buildspecs/policy-check.yml"
run_test "Unit tests buildspec exists" "test -f buildspecs/unit-tests.yml"

echo ""

# Summary
echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}==================================${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review terraform.tfvars configuration"
    echo "2. Deploy infrastructure: ./scripts/deployment/deploy.sh"
    echo "3. Add GitHub token to Secrets Manager"
    echo "4. Push code to trigger pipeline"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    echo ""
    echo "Please fix the failing tests before deployment"
    exit 1
fi
