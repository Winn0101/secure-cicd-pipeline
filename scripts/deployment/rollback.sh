#!/bin/bash

set -e

echo "Rolling back deployment..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PIPELINE_NAME=${1:-}
EXECUTION_ID=${2:-}

if [ -z "$PIPELINE_NAME" ]; then
    echo -e "${RED}Usage: $0 <pipeline_name> [execution_id]${NC}"
    exit 1
fi

echo "Pipeline: $PIPELINE_NAME"

if [ -z "$EXECUTION_ID" ]; then
    # Get latest execution
    echo -e "${YELLOW}Getting latest pipeline execution...${NC}"
    EXECUTION_ID=$(aws codepipeline list-pipeline-executions \
        --pipeline-name "$PIPELINE_NAME" \
        --max-results 1 \
        --query 'pipelineExecutionSummaries[0].pipelineExecutionId' \
        --output text)
fi

echo "Execution ID: $EXECUTION_ID"

# Stop pipeline execution
echo -e "${YELLOW}Stopping pipeline execution...${NC}"
aws codepipeline stop-pipeline-execution \
    --pipeline-name "$PIPELINE_NAME" \
    --pipeline-execution-id "$EXECUTION_ID" \
    --abandon \
    --reason "Manual rollback initiated"

echo -e "${GREEN}✓ Pipeline execution stopped${NC}"

# Get previous successful execution
echo -e "${YELLOW}Finding previous successful deployment...${NC}"
PREVIOUS_EXECUTION=$(aws codepipeline list-pipeline-executions \
    --pipeline-name "$PIPELINE_NAME" \
    --query 'pipelineExecutionSummaries[?status==`Succeeded`] | [1].pipelineExecutionId' \
    --output text)

if [ "$PREVIOUS_EXECUTION" = "None" ] || [ -z "$PREVIOUS_EXECUTION" ]; then
    echo -e "${RED}No previous successful execution found${NC}"
    exit 1
fi

echo "Previous successful execution: $PREVIOUS_EXECUTION"

# Create rollback plan
echo -e "${YELLOW}Creating rollback plan...${NC}"

cat > rollback-plan.json << EOL
{
  "pipeline_name": "$PIPELINE_NAME",
  "current_execution": "$EXECUTION_ID",
  "rollback_to_execution": "$PREVIOUS_EXECUTION",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "initiated_by": "$(whoami)"
}
EOL

echo "Rollback plan created: rollback-plan.json"

echo ""
echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}Rollback Summary${NC}"
echo -e "${GREEN}==================================${NC}"
echo "Pipeline: $PIPELINE_NAME"
echo "Stopped execution: $EXECUTION_ID"
echo "Rolling back to: $PREVIOUS_EXECUTION"
echo ""
echo -e "${YELLOW}To complete rollback:${NC}"
echo "1. Review rollback-plan.json"
echo "2. Redeploy from previous successful state"
echo "3. Verify application health"
echo ""
echo -e "${BLUE}Start rollback deployment:${NC}"
echo "aws codepipeline start-pipeline-execution --name $PIPELINE_NAME"
