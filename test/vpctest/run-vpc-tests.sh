#!/bin/bash
#
# VPC Network Test Runner for gits App
# =====================================
# Deploys a test EC2 instance in the PRIVATE SUBNET to verify the VPC
# architecture works correctly for both CodeBuild and Lambda functions.
#
# This tests:
# - NAT Gateway: CodeBuild needs this for git clone (SSH/HTTPS)
# - VPC Endpoints: Both CodeBuild and Lambda need these for AWS services
# - Security Isolation: No public IP, proper subnet placement
#

set -e

# Configuration
PROJECT_NAME="gits"
REGION="eu-west-3"
STACK_NAME="${PROJECT_NAME}-vpc-test"
ARTIFACT_BUCKET="${PROJECT_NAME}-artifacts"
WAIT_TIME_SECONDS=300  # 5 minutes for tests to complete
CLEANUP=${CLEANUP:-true}

# Store original credentials to allow re-assuming the role
ORIGINAL_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
ORIGINAL_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
ORIGINAL_AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --deploy      Deploy test stack only (no cleanup)"
    echo "  --results     Fetch and display results only"
    echo "  --cleanup     Delete test stack only"
    echo "  --full        Full test cycle: deploy, wait, results, cleanup (default)"
    echo "  --no-cleanup  Run full test but keep stack for debugging"
    echo "  --help        Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  REGION        AWS region (default: eu-west-3)"
    echo "  WAIT_TIME     Seconds to wait for tests (default: 300)"
    echo ""
}

# Function to assume the deployment role
assume_deployment_role() {
    print_info "Assuming CloudFormation deployment role..."
    
    # Get the role ARN from IAM stack
    ROLE_ARN=$(aws cloudformation describe-stacks \
        --stack-name "${PROJECT_NAME}-iam" \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFormationDeploymentRoleArn`].OutputValue' \
        --output text \
        --region "$REGION" 2>/dev/null)
    
    if [[ -z "$ROLE_ARN" ]] || [[ "$ROLE_ARN" == "None" ]]; then
        print_error "Could not find CloudFormation deployment role. Is the IAM stack deployed?"
        exit 1
    fi
    
    # Temporarily restore original credentials to assume role
    if [ -n "$ORIGINAL_AWS_ACCESS_KEY_ID" ]; then
        export AWS_ACCESS_KEY_ID="$ORIGINAL_AWS_ACCESS_KEY_ID"
        export AWS_SECRET_ACCESS_KEY="$ORIGINAL_AWS_SECRET_ACCESS_KEY"
        export AWS_SESSION_TOKEN="$ORIGINAL_AWS_SESSION_TOKEN"
    else
        unset AWS_ACCESS_KEY_ID
        unset AWS_SECRET_ACCESS_KEY
        unset AWS_SESSION_TOKEN
    fi
    
    ASSUME_ROLE_OUTPUT=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "vpc-test-runner" --region "$REGION")
    export AWS_ACCESS_KEY_ID=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SessionToken')
    
    print_success "Role assumed successfully"
}

# Function to get the latest Amazon Linux 2023 AMI
get_latest_ami() {
    print_info "Looking up latest Amazon Linux 2023 AMI..." >&2
    
    local ami_id
    # Try SSM parameter first
    ami_id=$(aws ssm get-parameter \
        --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
        --query 'Parameter.Value' \
        --output text \
        --region "$REGION" 2>/dev/null) || true
    
    # If SSM failed, try EC2 describe-images
    if [[ -z "$ami_id" ]] || [[ "$ami_id" == "None" ]]; then
        print_warning "SSM lookup failed, trying EC2 describe-images..." >&2
        ami_id=$(aws ec2 describe-images \
            --owners amazon \
            --filters "Name=name,Values=al2023-ami-2023*-kernel-*-x86_64" "Name=state,Values=available" \
            --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
            --output text \
            --region "$REGION" 2>/dev/null) || true
    fi
    
    if [[ -z "$ami_id" ]] || [[ "$ami_id" == "None" ]]; then
        print_error "Could not find Amazon Linux 2023 AMI" >&2
        exit 1
    fi
    
    print_success "Found AMI: $ami_id" >&2
    echo "$ami_id"
}

deploy_test_stack() {
    print_header "Deploying VPC Test Stack"
    
    # First assume deployment role (needed for AMI lookup and all operations)
    assume_deployment_role
    
    # Get the latest AMI ID
    AMI_ID=$(get_latest_ami)
    
    # Check if VPC stack exists
    if ! aws cloudformation describe-stacks --stack-name "${PROJECT_NAME}-vpc" --region "$REGION" &>/dev/null; then
        print_error "VPC stack '${PROJECT_NAME}-vpc' not found. Deploy it first."
        exit 1
    fi
    
    # Check if S3 bucket exists
    if ! aws s3 ls "s3://${ARTIFACT_BUCKET}" --region "$REGION" &>/dev/null; then
        print_error "S3 bucket '${ARTIFACT_BUCKET}' not found. Deploy infrastructure first."
        exit 1
    fi
    
    # Clean up old test results to avoid stale data
    print_info "Cleaning up old test results..."
    aws s3 rm "s3://${ARTIFACT_BUCKET}/vpc-tests/" --recursive --region "$REGION" 2>/dev/null || true
    
    # Upload test scripts to S3
    print_info "Uploading test scripts to S3..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    aws s3 cp "${SCRIPT_DIR}/private-subnet-tests.sh" "s3://${ARTIFACT_BUCKET}/scripts/private-subnet-tests.sh" --region "$REGION"
    
    print_success "Test scripts uploaded to S3"
    
    print_info "Deploying stack: ${STACK_NAME}"
    
    aws cloudformation deploy \
        --stack-name "$STACK_NAME" \
        --template-file "vpc-test.yaml" \
        --region "$REGION" \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameter-overrides \
            ProjectName="$PROJECT_NAME" \
            TestResultsBucket="$ARTIFACT_BUCKET" \
            AmiId="$AMI_ID" \
        --tags \
            Project="$PROJECT_NAME" \
            Purpose="vpc-security-test"
    
    print_success "Test stack deployed successfully"
    
    # Get instance IDs
    PRIVATE_INSTANCE=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`PrivateTestInstanceId`].OutputValue' \
        --output text)
    
    print_info "Private subnet test instance: $PRIVATE_INSTANCE"
    print_info "(Simulates both CodeBuild and Lambda network environments)"
}

wait_for_tests() {
    print_header "Waiting for Tests to Complete"
    
    print_info "Waiting ${WAIT_TIME_SECONDS} seconds for EC2 instances to run tests..."
    print_info "Tests include:"
    echo "  • NAT Gateway connectivity (SSH/HTTPS to GitHub for git clone)"
    echo "  • VPC Endpoints (S3, DynamoDB, Secrets Manager, EventBridge, ECR, CodeBuild)"
    echo "  • Security isolation (no public IP, private subnet verification)"
    echo "  • Route table verification (NAT Gateway route exists)"
    echo "  • DNS resolution"
    echo "  • NEGATIVE TESTS: Blocked ports, services without VPC endpoints"
    echo ""
    
    # Progress indicator
    for ((i=0; i<WAIT_TIME_SECONDS; i+=30)); do
        remaining=$((WAIT_TIME_SECONDS - i))
        echo -ne "\r  Waiting... ${remaining}s remaining    "
        sleep 30
    done
    echo -e "\r  Wait complete.                    "
    
    print_success "Wait period completed"
}

fetch_results() {
    print_header "Fetching Test Results"
    
    # Assume deployment role for AWS access
    assume_deployment_role
    
    # Invoke aggregator Lambda
    AGGREGATOR_FUNCTION="${PROJECT_NAME}-vpc-test-aggregator"
    
    print_info "Invoking test results aggregator..."
    
    LAMBDA_RESULT=$(aws lambda invoke \
        --function-name "$AGGREGATOR_FUNCTION" \
        --region "$REGION" \
        --payload '{}' \
        --cli-binary-format raw-in-base64-out \
        /tmp/vpc-test-results.json 2>&1 || echo "LAMBDA_ERROR")
    
    if [[ "$LAMBDA_RESULT" == *"LAMBDA_ERROR"* ]] || [[ "$LAMBDA_RESULT" == *"error"* ]]; then
        print_warning "Could not invoke aggregator Lambda, fetching results directly from S3..."
    fi
    
    # Download aggregated results
    print_info "Downloading results from S3..."
    
    aws s3 cp "s3://${ARTIFACT_BUCKET}/vpc-tests/aggregated.json" /tmp/vpc-aggregated.json --region "$REGION" 2>/dev/null || true
    
    # List all result files
    echo ""
    print_info "Test result files in S3:"
    aws s3 ls "s3://${ARTIFACT_BUCKET}/vpc-tests/" --region "$REGION" 2>/dev/null || print_warning "No results found yet"
    
    # Display results
    echo ""
    if [[ -f /tmp/vpc-aggregated.json ]]; then
        display_results /tmp/vpc-aggregated.json
    else
        # Try to fetch individual results
        print_warning "Aggregated results not available, fetching individual results..."
        
        for prefix in "private-subnet"; do
            LATEST=$(aws s3 ls "s3://${ARTIFACT_BUCKET}/vpc-tests/${prefix}-" --region "$REGION" 2>/dev/null | grep ".json" | sort | tail -1 | awk '{print $4}')
            if [[ -n "$LATEST" ]]; then
                aws s3 cp "s3://${ARTIFACT_BUCKET}/vpc-tests/${LATEST}" "/tmp/${prefix}-results.json" --region "$REGION"
                print_info "Results from ${prefix}:"
                cat "/tmp/${prefix}-results.json" | jq '.'
            fi
        done
    fi
}

display_results() {
    local results_file=$1
    
    print_header "VPC Security Test Results"
    
    if [[ ! -f "$results_file" ]]; then
        print_error "Results file not found: $results_file"
        return 1
    fi
    
    # Parse and display results
    OVERALL_STATUS=$(jq -r '.overall_summary.status // "UNKNOWN"' "$results_file")
    TOTAL=$(jq -r '.overall_summary.total_tests // 0' "$results_file")
    PASSED=$(jq -r '.overall_summary.passed // 0' "$results_file")
    FAILED=$(jq -r '.overall_summary.failed // 0' "$results_file")
    
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│                    TEST SUMMARY                        │"
    echo "├─────────────────────────────────────────────────────────┤"
    printf "│  Total Tests: %-40s │\n" "$TOTAL"
    printf "│  ${GREEN}Passed: %-43s${NC} │\n" "$PASSED"
    printf "│  ${RED}Failed: %-43s${NC} │\n" "$FAILED"
    echo "├─────────────────────────────────────────────────────────┤"
    
    if [[ "$OVERALL_STATUS" == "PASSED" ]]; then
        echo -e "│  Overall Status: ${GREEN}✓ PASSED${NC}                              │"
    else
        echo -e "│  Overall Status: ${RED}✗ FAILED${NC}                              │"
    fi
    echo "└─────────────────────────────────────────────────────────┘"
    
    echo ""
    
    # Display individual test suites
    SUITES=$(jq -r '.overall_summary.suites | length' "$results_file")
    
    for ((i=0; i<SUITES; i++)); do
        SUITE_NAME=$(jq -r ".overall_summary.suites[$i].name" "$results_file")
        SUBNET=$(jq -r ".overall_summary.suites[$i].subnet" "$results_file")
        
        echo ""
        print_info "Test Suite: $SUITE_NAME ($SUBNET subnet)"
        echo "─────────────────────────────────────────────────────────"
        
        # Display each test in the suite
        TESTS=$(jq -r ".overall_summary.suites[$i].tests | length" "$results_file")
        
        for ((j=0; j<TESTS; j++)); do
            TEST_NAME=$(jq -r ".overall_summary.suites[$i].tests[$j].name" "$results_file")
            TEST_PASSED=$(jq -r ".overall_summary.suites[$i].tests[$j].passed" "$results_file")
            TEST_DETAILS=$(jq -r ".overall_summary.suites[$i].tests[$j].details" "$results_file")
            
            if [[ "$TEST_PASSED" == "true" ]]; then
                printf "  ${GREEN}✓${NC} %-30s %s\n" "$TEST_NAME" "$TEST_DETAILS"
            else
                printf "  ${RED}✗${NC} %-30s %s\n" "$TEST_NAME" "$TEST_DETAILS"
            fi
        done
    done
    
    echo ""
    
    # Return exit code based on results
    if [[ "$OVERALL_STATUS" == "PASSED" ]]; then
        return 0
    else
        return 1
    fi
}

cleanup_test_stack() {
    print_header "Cleaning Up Test Stack"
    
    # Assume deployment role for AWS access
    assume_deployment_role
    
    print_info "Deleting stack: ${STACK_NAME}"
    
    aws cloudformation delete-stack \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
    
    print_info "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
    
    print_success "Test stack deleted successfully"
    
    # Keep test results in S3 for debugging/auditing
    print_info "Test results preserved in s3://${ARTIFACT_BUCKET}/vpc-tests/"
}

full_test_cycle() {
    print_header "VPC Security Test - Full Cycle"
    
    echo "This will:"
    echo "  1. Deploy test EC2 instances in your VPC"
    echo "  2. Wait for automated tests to complete"
    echo "  3. Aggregate and display results"
    if [[ "$CLEANUP" == "true" ]]; then
        echo "  4. Clean up test resources"
    else
        echo "  4. Keep test resources for debugging"
    fi
    echo ""
    
    deploy_test_stack
    wait_for_tests
    fetch_results
    RESULTS_EXIT_CODE=$?
    
    if [[ "$CLEANUP" == "true" ]]; then
        cleanup_test_stack
    else
        print_warning "Skipping cleanup. Remember to delete the stack manually:"
        echo "  aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION"
    fi
    
    exit $RESULTS_EXIT_CODE
}

# Parse command line arguments
case "${1:-}" in
    --deploy)
        deploy_test_stack
        ;;
    --results)
        fetch_results
        ;;
    --cleanup)
        cleanup_test_stack
        ;;
    --full)
        full_test_cycle
        ;;
    --no-cleanup)
        CLEANUP=false
        full_test_cycle
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    "")
        full_test_cycle
        ;;
    *)
        print_error "Unknown option: $1"
        usage
        exit 1
        ;;
esac
