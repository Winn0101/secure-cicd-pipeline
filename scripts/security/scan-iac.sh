#!/bin/bash

set -e

echo "🏗️  Scanning Infrastructure-as-Code for security issues..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCAN_DIR=${1:-.}
CONFIG_FILE=${2:-policies/security/checkov-config.yml}

# Create output directory
mkdir -p reports

echo "Scanning directory: $SCAN_DIR"
echo "Config file: $CONFIG_FILE"
echo ""

# Function to scan with Checkov
scan_with_checkov() {
    echo -e "${YELLOW}Running Checkov IaC scan...${NC}"
    
    if [ -f "$CONFIG_FILE" ]; then
        checkov \
            --config-file "$CONFIG_FILE" \
            --directory "$SCAN_DIR" \
            --output json \
            --output-file-path reports/ \
            --soft-fail || true
        
        # Also create human-readable report
        checkov \
            --config-file "$CONFIG_FILE" \
            --directory "$SCAN_DIR" \
            --output cli \
            > reports/checkov-scan.txt || true
    else
        checkov \
            --directory "$SCAN_DIR" \
            --framework terraform \
            --framework dockerfile \
            --output json \
            --output-file-path reports/ \
            --soft-fail || true
        
        checkov \
            --directory "$SCAN_DIR" \
            --framework terraform \
            --framework dockerfile \
            --output cli \
            > reports/checkov-scan.txt || true
    fi
    
    # Parse results
    if [ -f "reports/results_json.json" ]; then
        mv reports/results_json.json reports/checkov-scan.json
    fi
    
    if [ -f "reports/checkov-scan.json" ]; then
        passed=$(jq '.summary.passed' reports/checkov-scan.json 2>/dev/null || echo "0")
        failed=$(jq '.summary.failed' reports/checkov-scan.json 2>/dev/null || echo "0")
        skipped=$(jq '.summary.skipped' reports/checkov-scan.json 2>/dev/null || echo "0")
        
        echo ""
        echo "Checkov Summary:"
        echo "  Passed: $passed"
        echo "  Failed: $failed"
        echo "  Skipped: $skipped"
        
        return $failed
    else
        echo -e "${YELLOW}⚠ Could not parse Checkov results${NC}"
        return 0
    fi
}

# Function to check Terraform formatting
check_terraform_fmt() {
    echo -e "${YELLOW}Checking Terraform formatting...${NC}"
    
    if [ -d "$SCAN_DIR" ]; then
        # Find all .tf files
        tf_files=$(find "$SCAN_DIR" -name "*.tf" -type f)
        
        if [ -z "$tf_files" ]; then
            echo -e "${YELLOW}No Terraform files found${NC}"
            return 0
        fi
        
        # Check formatting
        if terraform fmt -check -recursive "$SCAN_DIR" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Terraform files are properly formatted${NC}"
            return 0
        else
            echo -e "${RED}✗ Terraform files need formatting${NC}"
            echo "Run: terraform fmt -recursive $SCAN_DIR"
            return 1
        fi
    fi
    
    return 0
}

# Function to validate Terraform
validate_terraform() {
    echo -e "${YELLOW}Validating Terraform configuration...${NC}"
    
    # Find directories with .tf files
    tf_dirs=$(find "$SCAN_DIR" -name "*.tf" -type f -exec dirname {} \; | sort -u)
    
    if [ -z "$tf_dirs" ]; then
        echo -e "${YELLOW}No Terraform directories found${NC}"
        return 0
    fi
    
    VALIDATION_FAILED=0
    
    for dir in $tf_dirs; do
        echo "Validating: $dir"
        
        # Initialize if needed
        if [ ! -d "$dir/.terraform" ]; then
            (cd "$dir" && terraform init -backend=false > /dev/null 2>&1) || true
        fi
        
        # Validate
        if (cd "$dir" && terraform validate > /dev/null 2>&1); then
            echo -e "${GREEN}✓ Valid${NC}"
        else
            echo -e "${RED}✗ Invalid${NC}"
            (cd "$dir" && terraform validate)
            VALIDATION_FAILED=1
        fi
    done
    
    return $VALIDATION_FAILED
}

# Function to check for hardcoded secrets in Terraform
check_terraform_secrets() {
    echo -e "${YELLOW}Scanning Terraform files for hardcoded secrets...${NC}"
    
    findings_file="reports/terraform-secrets.txt"
    > "$findings_file"
    
    # Patterns to search for in Terraform files
    patterns=(
        'password\s*=\s*"[^"]+"'
        'secret\s*=\s*"[^"]+"'
        'api_key\s*=\s*"[^"]+"'
        'access_key\s*=\s*"[^"]+"'
        'private_key\s*=\s*"[^"]+"'
    )
    
    SECRETS_FOUND=0
    
    for pattern in "${patterns[@]}"; do
        if grep -rniE "$pattern" "$SCAN_DIR" --include="*.tf" >> "$findings_file" 2>/dev/null; then
            SECRETS_FOUND=$((SECRETS_FOUND + 1))
        fi
    done
    
    if [ $SECRETS_FOUND -gt 0 ]; then
        echo -e "${RED}✗ Potential hardcoded secrets found in Terraform files${NC}"
        return 1
    else
        echo -e "${GREEN}✓ No hardcoded secrets found${NC}"
        return 0
    fi
}

# Function to check Dockerfile best practices
check_dockerfile() {
    echo -e "${YELLOW}Checking Dockerfile best practices...${NC}"
    
    # Find Dockerfiles
    dockerfiles=$(find "$SCAN_DIR" -name "Dockerfile*" -type f)
    
    if [ -z "$dockerfiles" ]; then
        echo -e "${YELLOW}No Dockerfiles found${NC}"
        return 0
    fi
    
    ISSUES=0
    
    for dockerfile in $dockerfiles; do
        echo "Checking: $dockerfile"
        
        # Check for latest tag
        if grep -qi "FROM.*:latest" "$dockerfile"; then
            echo -e "${RED}  ✗ Uses 'latest' tag${NC}"
            ISSUES=$((ISSUES + 1))
        fi
        
        # Check for USER instruction
        if ! grep -qi "^USER" "$dockerfile"; then
            echo -e "${YELLOW}  ⚠ Missing USER instruction (runs as root)${NC}"
            ISSUES=$((ISSUES + 1))
        fi
        
        # Check for HEALTHCHECK
        if ! grep -qi "^HEALTHCHECK" "$dockerfile"; then
            echo -e "${YELLOW}  ⚠ Missing HEALTHCHECK instruction${NC}"
        fi
        
        # Check for COPY with --chown
        if grep -q "^COPY " "$dockerfile" && ! grep -q "COPY --chown" "$dockerfile"; then
            echo -e "${YELLOW}  ⚠ COPY without --chown (may have permission issues)${NC}"
        fi
        
        if [ $ISSUES -eq 0 ]; then
            echo -e "${GREEN}  ✓ Dockerfile looks good${NC}"
        fi
    done
    
    return $ISSUES
}

# Main execution
main() {
    FAIL=0
    
    scan_with_checkov
    checkov_failed=$?
    
    check_terraform_fmt || FAIL=1
    
    validate_terraform || FAIL=1
    
    check_terraform_secrets || FAIL=1
    
    check_dockerfile || FAIL=1
    
    echo ""
    echo "==================================="
    
    if [ $checkov_failed -gt 0 ]; then
        echo -e "${RED}❌ IaC scan FAILED${NC}"
        echo -e "${RED}Found $checkov_failed Checkov violations${NC}"
        FAIL=1
    fi
    
    if [ $FAIL -eq 1 ]; then
        echo "Review reports/ directory for details"
        exit 1
    else
        echo -e "${GREEN}✅ IaC scan PASSED${NC}"
        exit 0
    fi
}

main
