#!/bin/bash

set -e

echo "🐳 Scanning container image for vulnerabilities..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

IMAGE_NAME=${1:-}
SEVERITY_THRESHOLD=${2:-HIGH}

if [ -z "$IMAGE_NAME" ]; then
    echo -e "${RED}Usage: $0 <image_name> [severity_threshold]${NC}"
    echo "Example: $0 myapp:latest HIGH"
    exit 1
fi

# Create output directory
mkdir -p reports

echo "Scanning image: $IMAGE_NAME"
echo "Severity threshold: $SEVERITY_THRESHOLD"
echo ""

# Function to scan with Trivy
scan_with_trivy() {
    echo -e "${YELLOW}Running Trivy vulnerability scan...${NC}"
    
    trivy image \
        --severity "$SEVERITY_THRESHOLD" \
        --format json \
        --output reports/trivy-scan.json \
        "$IMAGE_NAME"
    
    # Also create human-readable report
    trivy image \
        --severity "$SEVERITY_THRESHOLD" \
        --format table \
        --output reports/trivy-scan.txt \
        "$IMAGE_NAME"
    
    # Parse results
    critical_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' reports/trivy-scan.json)
    high_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' reports/trivy-scan.json)
    medium_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM")] | length' reports/trivy-scan.json)
    
    echo ""
    echo "Vulnerability Summary:"
    echo "  Critical: $critical_count"
    echo "  High: $high_count"
    echo "  Medium: $medium_count"
    
    # Create summary
    cat > reports/vulnerability-summary.json << EOL
{
  "image": "$IMAGE_NAME",
  "scan_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "vulnerabilities": {
    "critical": $critical_count,
    "high": $high_count,
    "medium": $medium_count
  }
}
EOL
    
    return 0
}

# Function to check base image
check_base_image() {
    echo -e "${YELLOW}Checking base image...${NC}"
    
    # Extract base image from Dockerfile if it exists
    if [ -f "Dockerfile" ]; then
        base_image=$(grep -i "^FROM" Dockerfile | head -1 | awk '{print $2}')
        echo "Base image: $base_image"
        
        # Check if using 'latest' tag
        if [[ "$base_image" == *":latest" ]]; then
            echo -e "${RED}✗ Using 'latest' tag is prohibited${NC}"
            return 1
        fi
        
        echo -e "${GREEN}✓ Base image check passed${NC}"
    fi
    
    return 0
}

# Function to check for secrets in image
check_image_secrets() {
    echo -e "${YELLOW}Scanning image for secrets...${NC}"
    
    trivy image \
        --scanners secret \
        --format json \
        --output reports/trivy-secrets.json \
        "$IMAGE_NAME"
    
    secret_count=$(jq '[.Results[]?.Secrets[]?] | length' reports/trivy-secrets.json 2>/dev/null || echo "0")
    
    if [ "$secret_count" -gt 0 ]; then
        echo -e "${RED}✗ Found $secret_count potential secrets in image${NC}"
        return 1
    else
        echo -e "${GREEN}✓ No secrets found in image${NC}"
        return 0
    fi
}

# Function to check image configuration
check_image_config() {
    echo -e "${YELLOW}Checking image configuration...${NC}"
    
    trivy image \
        --scanners config \
        --format json \
        --output reports/trivy-config.json \
        "$IMAGE_NAME"
    
    config_issues=$(jq '[.Results[]?.Misconfigurations[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL")] | length' reports/trivy-config.json 2>/dev/null || echo "0")
    
    if [ "$config_issues" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Found $config_issues configuration issues${NC}"
    else
        echo -e "${GREEN}✓ No critical configuration issues${NC}"
    fi
    
    return 0
}

# Main execution
main() {
    FAIL=0
    
    scan_with_trivy
    
    check_base_image || FAIL=1
    
    check_image_secrets || FAIL=1
    
    check_image_config
    
    echo ""
    echo "==================================="
    
    # Check vulnerability counts
    critical_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' reports/trivy-scan.json)
    high_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' reports/trivy-scan.json)
    
    if [ "$critical_count" -gt 0 ] || [ "$high_count" -gt 0 ]; then
        echo -e "${RED}❌ Container scan FAILED${NC}"
        echo -e "${RED}Found $critical_count critical and $high_count high vulnerabilities${NC}"
        FAIL=1
    fi
    
    if [ $FAIL -eq 1 ]; then
        echo "Review reports/ directory for details"
        exit 1
    else
        echo -e "${GREEN}✅ Container scan PASSED${NC}"
        exit 0
    fi
}

main
