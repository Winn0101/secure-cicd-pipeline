#!/bin/bash

set -e

echo "🔐 Scanning for secrets and sensitive data..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SECRETS_FOUND=0
SCAN_DIR=${1:-.}

# Create output directory
mkdir -p reports

# Function to scan with git-secrets
scan_git_secrets() {
    echo -e "${YELLOW}Running git-secrets scan...${NC}"
    
    # Initialize git-secrets in repo
    if [ -d .git ]; then
        git secrets --install -f || true
        git secrets --register-aws || true
        
        # Scan repository
        if git secrets --scan -r .; then
            echo -e "${GREEN}✓ No secrets found by git-secrets${NC}"
        else
            echo -e "${RED}✗ Secrets found by git-secrets!${NC}"
            SECRETS_FOUND=$((SECRETS_FOUND + 1))
        fi
    else
        echo -e "${YELLOW}Not a git repository, skipping git-secrets${NC}"
    fi
}

# Function to scan with custom patterns
scan_custom_patterns() {
    echo -e "${YELLOW}Running custom pattern scan...${NC}"
    
    # Patterns to search for
    patterns=(
        "password\s*=\s*['\"][^'\"]+['\"]"
        "api[_-]?key\s*=\s*['\"][^'\"]+['\"]"
        "secret[_-]?key\s*=\s*['\"][^'\"]+['\"]"
        "aws[_-]?access[_-]?key[_-]?id\s*=\s*['\"][^'\"]+['\"]"
        "aws[_-]?secret[_-]?access[_-]?key\s*=\s*['\"][^'\"]+['\"]"
        "AKIA[0-9A-Z]{16}"
        "-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----"
    )
    
    findings_file="reports/secrets-scan-custom.txt"
    > "$findings_file"
    
    for pattern in "${patterns[@]}"; do
        echo "Scanning for pattern: $pattern" >> "$findings_file"
        
        # Search for pattern
        if grep -rniE "$pattern" "$SCAN_DIR" \
            --exclude-dir={.git,.terraform,node_modules,venv} \
            --exclude="*.{zip,jar,tar,gz}" >> "$findings_file" 2>/dev/null; then
            
            echo -e "${RED}✗ Potential secrets found matching pattern${NC}"
            SECRETS_FOUND=$((SECRETS_FOUND + 1))
        fi
    done
    
    if [ $SECRETS_FOUND -eq 0 ]; then
        echo -e "${GREEN}✓ No secrets found by custom patterns${NC}"
    fi
}

# Function to scan for hardcoded IPs
scan_hardcoded_ips() {
    echo -e "${YELLOW}Scanning for hardcoded IPs...${NC}"
    
    findings_file="reports/hardcoded-ips.txt"
    > "$findings_file"
    
    # Look for hardcoded IPs (excluding common safe ranges)
    grep -rniE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$SCAN_DIR" \
        --exclude-dir={.git,.terraform,node_modules,venv} \
        --exclude="*.{zip,jar,tar,gz}" | \
        grep -v "127.0.0.1" | \
        grep -v "0.0.0.0" | \
        grep -v "255.255.255" > "$findings_file" || true
    
    if [ -s "$findings_file" ]; then
        echo -e "${YELLOW}⚠ Hardcoded IPs found (review needed)${NC}"
    else
        echo -e "${GREEN}✓ No suspicious hardcoded IPs found${NC}"
    fi
}

# Function to check for exposed environment variables
scan_env_files() {
    echo -e "${YELLOW}Checking for exposed .env files...${NC}"
    
    findings_file="reports/exposed-env-files.txt"
    > "$findings_file"
    
    find "$SCAN_DIR" -name ".env" -o -name ".env.*" -type f > "$findings_file" || true
    
    if [ -s "$findings_file" ]; then
        echo -e "${RED}✗ .env files found in repository!${NC}"
        cat "$findings_file"
        SECRETS_FOUND=$((SECRETS_FOUND + 1))
    else
        echo -e "${GREEN}✓ No .env files found${NC}"
    fi
}

# Main execution
main() {
    echo "Starting secrets scan on: $SCAN_DIR"
    echo "Report directory: reports/"
    echo ""
    
    scan_git_secrets
    scan_custom_patterns
    scan_hardcoded_ips
    scan_env_files
    
    echo ""
    echo "==================================="
    
    if [ $SECRETS_FOUND -gt 0 ]; then
        echo -e "${RED}❌ Secrets scan FAILED${NC}"
        echo -e "${RED}Found potential secrets or sensitive data${NC}"
        echo "Review reports/ directory for details"
        exit 1
    else
        echo -e "${GREEN}✅ Secrets scan PASSED${NC}"
        echo "No secrets detected"
        exit 0
    fi
}

main
