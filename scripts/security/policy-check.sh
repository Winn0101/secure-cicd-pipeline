#!/bin/bash

set -e

echo "📋 Running policy checks with OPA..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

POLICY_DIR=${1:-policies/opa}
INPUT_FILE=${2:-}
POLICY_TYPE=${3:-deployment}

# Create output directory
mkdir -p reports

if [ -z "$INPUT_FILE" ]; then
    echo -e "${RED}Usage: $0 <policy_dir> <input_file> [policy_type]${NC}"
    echo "Policy types: container, terraform, deployment"
    exit 1
fi

echo "Policy directory: $POLICY_DIR"
echo "Input file: $INPUT_FILE"
echo "Policy type: $POLICY_TYPE"
echo ""

# Function to run OPA evaluation
run_opa_eval() {
    local policy_file="$POLICY_DIR/${POLICY_TYPE}.rego"
    local data_file="$POLICY_DIR/data.json"
    
    if [ ! -f "$policy_file" ]; then
        echo -e "${RED}Policy file not found: $policy_file${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Evaluating policy: $policy_file${NC}"
    
    # Build OPA command
    opa_cmd="opa eval"
    opa_cmd="$opa_cmd --data $policy_file"
    
    if [ -f "$data_file" ]; then
        opa_cmd="$opa_cmd --data $data_file"
    fi
    
    opa_cmd="$opa_cmd --input $INPUT_FILE"
    opa_cmd="$opa_cmd --format pretty"
    opa_cmd="$opa_cmd 'data.${POLICY_TYPE}'"
    
    # Run evaluation and capture output
    eval $opa_cmd > reports/opa-eval-${POLICY_TYPE}.json
    
    # Parse results
    allowed=$(jq -r '.allow // false' reports/opa-eval-${POLICY_TYPE}.json 2>/dev/null || echo "false")
    violations=$(jq -r '.violations // []' reports/opa-eval-${POLICY_TYPE}.json 2>/dev/null || echo "[]")
    
    echo ""
    echo "Policy Evaluation Results:"
    echo "  Allowed: $allowed"
    
    violation_count=$(echo "$violations" | jq 'length' 2>/dev/null || echo "0")
    
    if [ "$violation_count" -gt 0 ]; then
        echo -e "${RED}  Violations: $violation_count${NC}"
        echo ""
        echo "Violations:"
        echo "$violations" | jq -r '.[]' 2>/dev/null || echo "$violations"
    else
        echo -e "${GREEN}  Violations: 0${NC}"
    fi
    
    return 0
}

# Function to test policy
test_opa_policy() {
    local policy_file="$POLICY_DIR/${POLICY_TYPE}.rego"
    
    echo -e "${YELLOW}Testing policy syntax...${NC}"
    
    if opa test "$POLICY_DIR" -v > reports/opa-test-${POLICY_TYPE}.txt 2>&1; then
        echo -e "${GREEN}✓ Policy syntax is valid${NC}"
        return 0
    else
        echo -e "${RED}✗ Policy syntax errors found${NC}"
        cat reports/opa-test-${POLICY_TYPE}.txt
        return 1
    fi
}

# Function to get policy decisions
get_policy_decision() {
    local allowed=$(jq -r '.allow // false' reports/opa-eval-${POLICY_TYPE}.json 2>/dev/null || echo "false")
    
    if [ "$allowed" == "true" ]; then
        return 0
    else
        return 1
    fi
}

# Function to generate policy report
generate_report() {
    local report_file="reports/policy-report-${POLICY_TYPE}.json"
    
    cat > "$report_file" << EOL
{
  "policy_type": "$POLICY_TYPE",
  "input_file": "$INPUT_FILE",
  "evaluation_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "results": $(cat reports/opa-eval-${POLICY_TYPE}.json)
}
EOL
    
    echo "Policy report saved: $report_file"
}

# Main execution
main() {
    test_opa_policy || exit 1
    
    run_opa_eval
    
    generate_report
    
    echo ""
    echo "==================================="
    
    if get_policy_decision; then
        echo -e "${GREEN}✅ Policy check PASSED${NC}"
        exit 0
    else
        echo -e "${RED}❌ Policy check FAILED${NC}"
        echo "Policy violations detected"
        exit 1
    fi
}

main
