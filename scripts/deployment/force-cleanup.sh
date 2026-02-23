#!/bin/bash

set -e

echo "🔥 Force Cleanup - Removes all resources matching project name"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_PREFIX="secure-cicd"

echo -e "${RED}⚠️  WARNING: This will forcefully delete ALL resources with prefix '$PROJECT_PREFIX'${NC}"
echo ""
read -p "Type 'force-delete' to confirm: " confirm

if [ "$confirm" != "force-delete" ]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting force cleanup...${NC}"

# Function to delete resources
delete_resources() {
    local resource_type=$1
    local list_command=$2
    local delete_command=$3
    
    echo -e "${YELLOW}Cleaning $resource_type...${NC}"
    
    eval "$list_command" | while read -r resource; do
        if [ -n "$resource" ]; then
            echo "  Deleting: $resource"
            eval "$delete_command $resource" 2>/dev/null || true
        fi
    done
}

# CodePipeline
echo -e "${YELLOW}1. CodePipeline...${NC}"
aws codepipeline list-pipelines --query "pipelines[?starts_with(name, '$PROJECT_PREFIX')].name" --output text 2>/dev/null | tr '\t' '\n' | while read pipeline; do
    if [ -n "$pipeline" ]; then
        echo "  Deleting pipeline: $pipeline"
        aws codepipeline delete-pipeline --name "$pipeline" 2>/dev/null || true
    fi
done

# CodeBuild
echo -e "${YELLOW}2. CodeBuild Projects...${NC}"
aws codebuild list-projects --query "projects[?starts_with(@, '$PROJECT_PREFIX')]" --output text 2>/dev/null | tr '\t' '\n' | while read project; do
    if [ -n "$project" ]; then
        echo "  Deleting project: $project"
        aws codebuild delete-project --name "$project" 2>/dev/null || true
    fi
done

# ECR Repositories
echo -e "${YELLOW}3. ECR Repositories...${NC}"
aws ecr describe-repositories --query "repositories[?starts_with(repositoryName, '$PROJECT_PREFIX')].repositoryName" --output text 2>/dev/null | tr '\t' '\n' | while read repo; do
    if [ -n "$repo" ]; then
        echo "  Deleting repository: $repo"
        aws ecr delete-repository --repository-name "$repo" --force 2>/dev/null || true
    fi
done

# S3 Buckets
echo -e "${YELLOW}4. S3 Buckets...${NC}"
aws s3api list-buckets --query "Buckets[?starts_with(Name, '$PROJECT_PREFIX')].Name" --output text 2>/dev/null | tr '\t' '\n' | while read bucket; do
    if [ -n "$bucket" ]; then
        echo "  Emptying bucket: $bucket"
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
        echo "  Deleting bucket: $bucket"
        aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
    fi
done

# DynamoDB Tables
echo -e "${YELLOW}5. DynamoDB Tables...${NC}"
aws dynamodb list-tables --query "TableNames[?starts_with(@, '$PROJECT_PREFIX')]" --output text 2>/dev/null | tr '\t' '\n' | while read table; do
    if [ -n "$table" ]; then
        echo "  Deleting table: $table"
        aws dynamodb delete-table --table-name "$table" 2>/dev/null || true
    fi
done

# SNS Topics
echo -e "${YELLOW}6. SNS Topics...${NC}"
aws sns list-topics --query "Topics[?contains(TopicArn, '$PROJECT_PREFIX')].TopicArn" --output text 2>/dev/null | tr '\t' '\n' | while read topic; do
    if [ -n "$topic" ]; then
        echo "  Deleting topic: $topic"
        aws sns delete-topic --topic-arn "$topic" 2>/dev/null || true
    fi
done

# Secrets Manager
echo -e "${YELLOW}7. Secrets Manager...${NC}"
aws secretsmanager list-secrets --query "SecretList[?starts_with(Name, '$PROJECT_PREFIX')].Name" --output text 2>/dev/null | tr '\t' '\n' | while read secret; do
    if [ -n "$secret" ]; then
        echo "  Deleting secret: $secret"
        aws secretsmanager delete-secret --secret-id "$secret" --force-delete-without-recovery 2>/dev/null || true
    fi
done

# KMS Keys
echo -e "${YELLOW}8. KMS Keys...${NC}"
aws kms list-aliases --query "Aliases[?starts_with(AliasName, 'alias/$PROJECT_PREFIX')].TargetKeyId" --output text 2>/dev/null | tr '\t' '\n' | while read key; do
    if [ -n "$key" ]; then
        echo "  Scheduling deletion for key: $key"
        aws kms schedule-key-deletion --key-id "$key" --pending-window-in-days 7 2>/dev/null || true
    fi
done

# CloudWatch Log Groups
echo -e "${YELLOW}9. CloudWatch Log Groups...${NC}"
aws logs describe-log-groups --query "logGroups[?starts_with(logGroupName, '/aws/codebuild/$PROJECT_PREFIX') || starts_with(logGroupName, '/aws/codepipeline/$PROJECT_PREFIX')].logGroupName" --output text 2>/dev/null | tr '\t' '\n' | while read log_group; do
    if [ -n "$log_group" ]; then
        echo "  Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
    fi
done

# IAM Roles
echo -e "${YELLOW}10. IAM Roles...${NC}"
aws iam list-roles --query "Roles[?starts_with(RoleName, '$PROJECT_PREFIX')].RoleName" --output text 2>/dev/null | tr '\t' '\n' | while read role; do
    if [ -n "$role" ]; then
        echo "  Detaching policies from role: $role"
        
        # Detach managed policies
        aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | tr '\t' '\n' | while read policy; do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
        done
        
        # Delete inline policies
        aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text 2>/dev/null | tr '\t' '\n' | while read policy; do
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
        done
        
        echo "  Deleting role: $role"
        aws iam delete-role --role-name "$role" 2>/dev/null || true
    fi
done

# EventBridge Rules
echo -e "${YELLOW}11. EventBridge Rules...${NC}"
aws events list-rules --query "Rules[?starts_with(Name, '$PROJECT_PREFIX')].Name" --output text 2>/dev/null | tr '\t' '\n' | while read rule; do
    if [ -n "$rule" ]; then
        echo "  Removing targets from rule: $rule"
        TARGETS=$(aws events list-targets-by-rule --rule "$rule" --query 'Targets[].Id' --output text 2>/dev/null)
        if [ -n "$TARGETS" ]; then
            aws events remove-targets --rule "$rule" --ids $TARGETS 2>/dev/null || true
        fi
        
        echo "  Deleting rule: $rule"
        aws events delete-rule --name "$rule" 2>/dev/null || true
    fi
done

echo ""
echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}Force Cleanup Complete!${NC}"
echo -e "${GREEN}==================================${NC}"
echo ""
echo -e "${YELLOW}Note: Some resources may take time to fully delete${NC}"
