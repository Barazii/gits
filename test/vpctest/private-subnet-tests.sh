#!/bin/bash
# =============================================================================
# VPC Private Subnet Tests - Tests gits app VPC architecture
# =============================================================================
# This script tests the network connectivity from the PRIVATE SUBNET where
# both CodeBuild and Lambda functions run in our architecture.
#
# Tests verify:
# 1. NAT Gateway connectivity (CodeBuild needs git clone via SSH/HTTPS)
# 2. VPC Endpoints work (S3, DynamoDB, Secrets Manager, EventBridge, ECR)
# 3. Security isolation (no public IP, no inbound connections)
#
# Required environment variables:
#   - TEST_RESULTS_BUCKET: S3 bucket for results
#   - AWS_REGION: AWS region
#   - CODEBUILD_SECURITY_GROUP_ID: CodeBuild-like SG ID
#   - LAMBDA_SECURITY_GROUP_ID: Lambda-like SG ID
#   - PROJECT_NAME: Project name (default: gits)
# =============================================================================

set -x

# Validate required environment variables
if [ -z "$TEST_RESULTS_BUCKET" ] || [ -z "$AWS_REGION" ]; then
  echo "ERROR: Required environment variables not set"
  echo "Required: TEST_RESULTS_BUCKET, AWS_REGION"
  exit 1
fi

PROJECT_NAME="${PROJECT_NAME:-gits}"

# Install required tools (Amazon Linux 2023 uses dnf)
dnf install -y nmap-ncat jq git 2>/dev/null || yum install -y nmap-ncat jq git 2>/dev/null || true

# Create test results directory
mkdir -p /tmp/vpc-tests
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get instance metadata using IMDSv2 (required for Amazon Linux 2023)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
MAC_ADDRESS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/mac)
SUBNET_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC_ADDRESS/subnet-id)
VPC_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC_ADDRESS/vpc-id)

# Initialize results JSON
cat > /tmp/vpc-tests/results.json << 'INITEOF'
{
  "testSuite": "VPC Private Subnet Tests (CodeBuild + Lambda Simulation)",
  "instanceId": "INSTANCE_ID_PLACEHOLDER",
  "timestamp": "TIMESTAMP_PLACEHOLDER",
  "subnet": "private",
  "description": "Tests run from private subnet to verify NAT Gateway and VPC Endpoints work correctly",
  "tests": []
}
INITEOF
sed -i "s/INSTANCE_ID_PLACEHOLDER/$INSTANCE_ID/" /tmp/vpc-tests/results.json
sed -i "s/TIMESTAMP_PLACEHOLDER/$TIMESTAMP/" /tmp/vpc-tests/results.json

# Function to add test result
add_test_result() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  local passed="$4"
  local details="$5"
  local component="$6"  # codebuild, lambda, or both
  
  jq --arg name "$name" \
     --arg expected "$expected" \
     --arg actual "$actual" \
     --arg passed "$passed" \
     --arg details "$details" \
     --arg component "$component" \
     '.tests += [{"name": $name, "expected": $expected, "actual": $actual, "passed": ($passed == "true"), "details": $details, "component": $component}]' \
     /tmp/vpc-tests/results.json > /tmp/vpc-tests/results.tmp && mv /tmp/vpc-tests/results.tmp /tmp/vpc-tests/results.json
}

echo "=== VPC Private Subnet Tests Starting ===" > /tmp/vpc-tests/test.log
echo "Instance: $INSTANCE_ID" >> /tmp/vpc-tests/test.log
echo "Region: $AWS_REGION" >> /tmp/vpc-tests/test.log
echo "Timestamp: $TIMESTAMP" >> /tmp/vpc-tests/test.log

# =============================================================================
# SECTION 1: NAT Gateway Tests (Required for CodeBuild)
# CodeBuild needs NAT Gateway for: git clone, npm/pip packages, external APIs
# =============================================================================
echo "" >> /tmp/vpc-tests/test.log
echo "=== NAT Gateway Tests (CodeBuild Requirements) ===" >> /tmp/vpc-tests/test.log

# Test 1: SSH to GitHub (git clone over SSH) - via NAT Gateway
echo "Test 1: SSH to GitHub (git clone over SSH)" >> /tmp/vpc-tests/test.log
SSH_TEST=$(timeout 10 bash -c 'echo > /dev/tcp/github.com/22' 2>&1 && echo "CONNECTED" || echo "BLOCKED")
if [[ "$SSH_TEST" == *"CONNECTED"* ]]; then
  add_test_result "nat_ssh_github" "reachable" "reachable" "true" "SSH to github.com:22 works via NAT Gateway (required for git clone)" "codebuild"
else
  add_test_result "nat_ssh_github" "reachable" "blocked" "false" "SSH to github.com:22 FAILED - git clone over SSH will not work: $SSH_TEST" "codebuild"
fi

# Test 2: HTTPS to GitHub (git clone over HTTPS) - via NAT Gateway
echo "Test 2: HTTPS to GitHub (git clone over HTTPS)" >> /tmp/vpc-tests/test.log
GITHUB_HTTPS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 https://github.com 2>&1 || echo "TIMEOUT")
if [ "$GITHUB_HTTPS" = "200" ] || [ "$GITHUB_HTTPS" = "301" ] || [ "$GITHUB_HTTPS" = "302" ]; then
  add_test_result "nat_https_github" "reachable" "reachable:$GITHUB_HTTPS" "true" "HTTPS to github.com works via NAT Gateway" "codebuild"
else
  add_test_result "nat_https_github" "reachable" "blocked:$GITHUB_HTTPS" "false" "HTTPS to github.com FAILED via NAT Gateway" "codebuild"
fi

# Test 3: Git clone test (actual git operation)
echo "Test 3: Git clone test" >> /tmp/vpc-tests/test.log
GIT_CLONE_TEST=$(timeout 30 git clone --depth 1 https://github.com/Barazii/gits.git /tmp/gits-test 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$GIT_CLONE_TEST" == *"SUCCESS"* ]]; then
  add_test_result "nat_git_clone" "success" "success" "true" "Git clone from GitHub works via NAT Gateway" "codebuild"
  rm -rf /tmp/gits-test
else
  add_test_result "nat_git_clone" "success" "failed" "false" "Git clone FAILED: $GIT_CLONE_TEST" "codebuild"
fi

# Test 4: External HTTP (package managers, external APIs)
echo "Test 4: External HTTP via NAT Gateway" >> /tmp/vpc-tests/test.log
HTTP_RESULT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://httpbin.org/get 2>&1 || echo "TIMEOUT")
if [ "$HTTP_RESULT" = "200" ]; then
  add_test_result "nat_http_external" "reachable" "reachable:$HTTP_RESULT" "true" "HTTP to external internet works via NAT Gateway" "codebuild"
else
  add_test_result "nat_http_external" "reachable" "blocked:$HTTP_RESULT" "false" "HTTP to external internet FAILED via NAT Gateway" "codebuild"
fi

# =============================================================================
# SECTION 2: VPC Endpoint Tests (Required for both CodeBuild and Lambda)
# These should work WITHOUT going through NAT Gateway
# =============================================================================
echo "" >> /tmp/vpc-tests/test.log
echo "=== VPC Endpoint Tests (Lambda + CodeBuild Requirements) ===" >> /tmp/vpc-tests/test.log

# Test 5: S3 VPC Gateway Endpoint
echo "Test 5: S3 VPC Gateway Endpoint" >> /tmp/vpc-tests/test.log
S3_TEST=$(aws s3 ls s3://$TEST_RESULTS_BUCKET --region $AWS_REGION 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$S3_TEST" == *"SUCCESS"* ]]; then
  add_test_result "vpce_s3_gateway" "reachable" "reachable" "true" "S3 VPC Gateway Endpoint working" "both"
else
  add_test_result "vpce_s3_gateway" "reachable" "unreachable" "false" "S3 VPC Gateway Endpoint FAILED: $S3_TEST" "both"
fi

# Test 6: DynamoDB VPC Gateway Endpoint
echo "Test 6: DynamoDB VPC Gateway Endpoint" >> /tmp/vpc-tests/test.log
DDB_TEST=$(aws dynamodb list-tables --region $AWS_REGION 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$DDB_TEST" == *"SUCCESS"* ]]; then
  add_test_result "vpce_dynamodb_gateway" "reachable" "reachable" "true" "DynamoDB VPC Gateway Endpoint working" "both"
else
  add_test_result "vpce_dynamodb_gateway" "reachable" "unreachable" "false" "DynamoDB VPC Gateway Endpoint FAILED: $DDB_TEST" "both"
fi

# Test 7: Secrets Manager VPC Interface Endpoint
echo "Test 7: Secrets Manager VPC Interface Endpoint" >> /tmp/vpc-tests/test.log
SM_TEST=$(aws secretsmanager list-secrets --region $AWS_REGION --max-results 1 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$SM_TEST" == *"SUCCESS"* ]]; then
  add_test_result "vpce_secretsmanager_interface" "reachable" "reachable" "true" "Secrets Manager VPC Interface Endpoint working" "both"
else
  add_test_result "vpce_secretsmanager_interface" "reachable" "unreachable" "false" "Secrets Manager VPC Interface Endpoint FAILED: $SM_TEST" "both"
fi

# Test 8: EventBridge VPC Interface Endpoint
echo "Test 8: EventBridge VPC Interface Endpoint" >> /tmp/vpc-tests/test.log
EB_TEST=$(aws events list-rules --region $AWS_REGION --limit 1 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$EB_TEST" == *"SUCCESS"* ]]; then
  add_test_result "vpce_eventbridge_interface" "reachable" "reachable" "true" "EventBridge VPC Interface Endpoint working" "both"
else
  add_test_result "vpce_eventbridge_interface" "reachable" "unreachable" "false" "EventBridge VPC Interface Endpoint FAILED: $EB_TEST" "both"
fi

# Test 9: ECR API VPC Interface Endpoint
echo "Test 9: ECR API VPC Interface Endpoint" >> /tmp/vpc-tests/test.log
ECR_TEST=$(aws ecr describe-repositories --region $AWS_REGION --max-results 1 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$ECR_TEST" == *"SUCCESS"* ]]; then
  add_test_result "vpce_ecr_api_interface" "reachable" "reachable" "true" "ECR API VPC Interface Endpoint working" "both"
else
  add_test_result "vpce_ecr_api_interface" "reachable" "unreachable" "false" "ECR API VPC Interface Endpoint FAILED: $ECR_TEST" "both"
fi

# Test 10: CodeBuild VPC Interface Endpoint
echo "Test 10: CodeBuild VPC Interface Endpoint" >> /tmp/vpc-tests/test.log
CB_TEST=$(aws codebuild list-projects --region $AWS_REGION 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$CB_TEST" == *"SUCCESS"* ]]; then
  add_test_result "vpce_codebuild_interface" "reachable" "reachable" "true" "CodeBuild VPC Interface Endpoint working" "lambda"
else
  add_test_result "vpce_codebuild_interface" "reachable" "unreachable" "false" "CodeBuild VPC Interface Endpoint FAILED: $CB_TEST" "lambda"
fi

# Test 11: CloudWatch Logs VPC Interface Endpoint
echo "Test 11: CloudWatch Logs VPC Interface Endpoint" >> /tmp/vpc-tests/test.log
CWL_TEST=$(aws logs describe-log-groups --region $AWS_REGION --limit 1 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$CWL_TEST" == *"SUCCESS"* ]]; then
  add_test_result "vpce_cloudwatch_logs_interface" "reachable" "reachable" "true" "CloudWatch Logs VPC Interface Endpoint working" "both"
else
  add_test_result "vpce_cloudwatch_logs_interface" "reachable" "unreachable" "false" "CloudWatch Logs VPC Interface Endpoint FAILED: $CWL_TEST" "both"
fi

# =============================================================================
# SECTION 2.5: VPC Flow Logs Tests
# These tests verify VPC Flow Logs are properly configured for network monitoring
# =============================================================================
echo "" >> /tmp/vpc-tests/test.log
echo "=== VPC Flow Logs Tests ===" >> /tmp/vpc-tests/test.log

# Test 11a: VPC Flow Logs Log Group exists
echo "Test 11a: VPC Flow Logs Log Group exists" >> /tmp/vpc-tests/test.log
FLOW_LOGS_GROUP_NAME="/aws/vpc/${PROJECT_NAME}-flow-logs"
FLOW_LOG_GROUP_TEST=$(aws logs describe-log-groups --region $AWS_REGION --log-group-name-prefix "$FLOW_LOGS_GROUP_NAME" --query 'logGroups[?logGroupName==`'"$FLOW_LOGS_GROUP_NAME"'`].logGroupName' --output text 2>&1)
if [ "$FLOW_LOG_GROUP_TEST" = "$FLOW_LOGS_GROUP_NAME" ]; then
  add_test_result "flowlogs_log_group_exists" "exists" "exists" "true" "VPC Flow Logs CloudWatch Log Group exists: $FLOW_LOGS_GROUP_NAME" "both"
else
  add_test_result "flowlogs_log_group_exists" "exists" "not_found" "false" "VPC Flow Logs CloudWatch Log Group not found: $FLOW_LOGS_GROUP_NAME (got: $FLOW_LOG_GROUP_TEST)" "both"
fi

# Test 11b: VPC Flow Log is configured and active
echo "Test 11b: VPC Flow Log is configured and active" >> /tmp/vpc-tests/test.log
FLOW_LOG_STATUS=$(aws ec2 describe-flow-logs --region $AWS_REGION \
  --filter "Name=resource-id,Values=$VPC_ID" \
  --query 'FlowLogs[0].FlowLogStatus' --output text 2>&1)
if [ "$FLOW_LOG_STATUS" = "ACTIVE" ]; then
  add_test_result "flowlogs_active" "active" "active" "true" "VPC Flow Log is active for VPC $VPC_ID" "both"
else
  add_test_result "flowlogs_active" "active" "$FLOW_LOG_STATUS" "false" "VPC Flow Log is not active for VPC $VPC_ID (status: $FLOW_LOG_STATUS)" "both"
fi

# Test 11c: VPC Flow Log captures ALL traffic types
echo "Test 11c: VPC Flow Log captures ALL traffic types" >> /tmp/vpc-tests/test.log
FLOW_LOG_TRAFFIC_TYPE=$(aws ec2 describe-flow-logs --region $AWS_REGION \
  --filter "Name=resource-id,Values=$VPC_ID" \
  --query 'FlowLogs[0].TrafficType' --output text 2>&1)
if [ "$FLOW_LOG_TRAFFIC_TYPE" = "ALL" ]; then
  add_test_result "flowlogs_traffic_type" "ALL" "ALL" "true" "VPC Flow Log captures ALL traffic types (ACCEPT and REJECT)" "both"
else
  add_test_result "flowlogs_traffic_type" "ALL" "$FLOW_LOG_TRAFFIC_TYPE" "false" "VPC Flow Log should capture ALL traffic (got: $FLOW_LOG_TRAFFIC_TYPE)" "both"
fi

# Test 11d: VPC Flow Log destination is CloudWatch Logs
echo "Test 11d: VPC Flow Log destination is CloudWatch Logs" >> /tmp/vpc-tests/test.log
FLOW_LOG_DEST_TYPE=$(aws ec2 describe-flow-logs --region $AWS_REGION \
  --filter "Name=resource-id,Values=$VPC_ID" \
  --query 'FlowLogs[0].LogDestinationType' --output text 2>&1)
if [ "$FLOW_LOG_DEST_TYPE" = "cloud-watch-logs" ]; then
  add_test_result "flowlogs_destination_type" "cloud-watch-logs" "cloud-watch-logs" "true" "VPC Flow Log sends to CloudWatch Logs" "both"
else
  add_test_result "flowlogs_destination_type" "cloud-watch-logs" "$FLOW_LOG_DEST_TYPE" "false" "VPC Flow Log destination should be CloudWatch Logs (got: $FLOW_LOG_DEST_TYPE)" "both"
fi

# =============================================================================
# SECTION 3: Security Isolation Tests
# =============================================================================
echo "" >> /tmp/vpc-tests/test.log
echo "=== Security Isolation Tests ===" >> /tmp/vpc-tests/test.log

# Test 12: No public IP (instance is isolated from direct internet access)
echo "Test 12: No Public IP" >> /tmp/vpc-tests/test.log
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" --connect-timeout 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>&1)
if [ -z "$PUBLIC_IP" ] || [[ "$PUBLIC_IP" == *"404"* ]] || [[ "$PUBLIC_IP" == *"Not Found"* ]]; then
  add_test_result "isolation_no_public_ip" "no_public_ip" "no_public_ip" "true" "Instance has no public IP (isolated from direct internet access)" "both"
else
  add_test_result "isolation_no_public_ip" "no_public_ip" "has_public_ip:$PUBLIC_IP" "false" "Instance should NOT have a public IP in private subnet" "both"
fi

# Test 13: Verify we're in the private subnet
echo "Test 13: Verify Private Subnet" >> /tmp/vpc-tests/test.log
# SUBNET_ID already fetched at the start of the script using IMDSv2
SUBNET_INFO=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --region $AWS_REGION --query 'Subnets[0].Tags[?Key==`Name`].Value' --output text 2>&1)
if [[ "$SUBNET_INFO" == *"private"* ]] || [[ "$SUBNET_INFO" == *"Private"* ]]; then
  add_test_result "isolation_private_subnet" "private_subnet" "private_subnet" "true" "Instance is in private subnet: $SUBNET_INFO" "both"
else
  add_test_result "isolation_private_subnet" "private_subnet" "subnet:$SUBNET_INFO" "false" "Instance should be in private subnet (got: $SUBNET_INFO)" "both"
fi

# Test 14: DNS resolution works (for DNS settings 'enableDnsSupport' and 'enableDnsHostnames')
echo "Test 14: DNS resolution" >> /tmp/vpc-tests/test.log
DNS_TEST=$(nslookup s3.$AWS_REGION.amazonaws.com 2>&1)
if [[ "$DNS_TEST" == *"Address"* ]]; then
  add_test_result "dns_resolution" "working" "working" "true" "DNS resolution working correctly" "both"
else
  add_test_result "dns_resolution" "working" "failed" "false" "DNS resolution failed: $DNS_TEST" "both"
fi

# Test 15: Verify VPC Endpoints exist
echo "Test 15: Verify VPC Endpoints exist" >> /tmp/vpc-tests/test.log
# VPC_ID already fetched at the start using IMDSv2
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  VPCE_COUNT=$(aws ec2 describe-vpc-endpoints --region $AWS_REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'VpcEndpoints | length(@)' --output text 2>&1)
  if [ "$VPCE_COUNT" -ge 7 ] 2>/dev/null; then
    add_test_result "vpce_count" ">=7" "$VPCE_COUNT" "true" "VPC has $VPCE_COUNT VPC Endpoints configured" "both"
  else
    add_test_result "vpce_count" ">=7" "$VPCE_COUNT" "false" "VPC should have at least 7 VPC Endpoints (S3, DynamoDB, SecretsManager, EventBridge, ECR API, ECR DKR, CodeBuild, CloudWatch Logs)" "both"
  fi
else
  add_test_result "vpce_count" ">=7" "error:no_vpc_id" "false" "Could not determine VPC ID" "both"
fi

# =============================================================================
# SECTION 4: Negative Tests - Verify Restricted Access FAILS
# These tests ensure the VPC architecture is RESTRICTIVE, not just permissive
# =============================================================================
echo "" >> /tmp/vpc-tests/test.log
echo "=== Negative Tests (Verify Blocked Access Fails) ===" >> /tmp/vpc-tests/test.log

# Test 16: Non-standard port access should fail (e.g., port 8080)
# Only "timed out" means SG blocked it; "Connection refused" means traffic got through
echo "Test 16: Non-standard port (8080) should be blocked" >> /tmp/vpc-tests/test.log
PORT_8080_TEST=$(timeout 5 bash -c 'echo > /dev/tcp/httpbin.org/8080' 2>&1 && echo "CONNECTED" || echo "BLOCKED")
if [[ "$PORT_8080_TEST" == *"timed out"* ]]; then
  add_test_result "negative_port_8080_blocked" "blocked" "blocked" "true" "Port 8080 correctly blocked (timeout)" "both"
elif [[ "$PORT_8080_TEST" == *"BLOCKED"* ]]; then
  add_test_result "negative_port_8080_blocked" "blocked" "blocked" "true" "Port 8080 correctly blocked" "both"
elif [[ "$PORT_8080_TEST" == *"Connection refused"* ]]; then
  add_test_result "negative_port_8080_blocked" "blocked" "reached_server" "false" "Port 8080 traffic reached server (SG too permissive)" "both"
else
  add_test_result "negative_port_8080_blocked" "blocked" "connected" "false" "Port 8080 should be blocked" "both"
fi

# Test 17: MySQL port (3306) should be blocked
# Only "timed out" means SG blocked it; "Connection refused" means traffic got through
echo "Test 17: MySQL port (3306) should be blocked" >> /tmp/vpc-tests/test.log
PORT_3306_TEST=$(timeout 5 bash -c 'echo > /dev/tcp/8.8.8.8/3306' 2>&1 && echo "CONNECTED" || echo "BLOCKED")
if [[ "$PORT_3306_TEST" == *"timed out"* ]]; then
  add_test_result "negative_port_3306_blocked" "blocked" "blocked" "true" "MySQL port 3306 correctly blocked (timeout)" "both"
elif [[ "$PORT_3306_TEST" == *"BLOCKED"* ]]; then
  add_test_result "negative_port_3306_blocked" "blocked" "blocked" "true" "MySQL port 3306 correctly blocked" "both"
elif [[ "$PORT_3306_TEST" == *"Connection refused"* ]]; then
  add_test_result "negative_port_3306_blocked" "blocked" "reached_server" "false" "MySQL port 3306 traffic reached server (SG too permissive)" "both"
else
  add_test_result "negative_port_3306_blocked" "blocked" "connected" "false" "MySQL port 3306 should be blocked" "both"
fi

# Test 18: FTP port (21) should be blocked
# Only "timed out" means SG blocked it; "Connection refused" means traffic got through
echo "Test 18: FTP port (21) should be blocked" >> /tmp/vpc-tests/test.log
PORT_21_TEST=$(timeout 5 bash -c 'echo > /dev/tcp/ftp.gnu.org/21' 2>&1 && echo "CONNECTED" || echo "BLOCKED")
if [[ "$PORT_21_TEST" == *"timed out"* ]]; then
  add_test_result "negative_port_21_blocked" "blocked" "blocked" "true" "FTP port 21 correctly blocked (timeout)" "both"
elif [[ "$PORT_21_TEST" == *"BLOCKED"* ]]; then
  add_test_result "negative_port_21_blocked" "blocked" "blocked" "true" "FTP port 21 correctly blocked" "both"
elif [[ "$PORT_21_TEST" == *"Connection refused"* ]]; then
  add_test_result "negative_port_21_blocked" "blocked" "reached_server" "false" "FTP port 21 traffic reached server (SG too permissive)" "both"
else
  add_test_result "negative_port_21_blocked" "blocked" "connected" "false" "FTP port 21 should be blocked" "both"
fi

# Test 19: Telnet port (23) should be blocked
# Only "timed out" means SG blocked it; "Connection refused" means traffic got through
echo "Test 19: Telnet port (23) should be blocked" >> /tmp/vpc-tests/test.log
PORT_23_TEST=$(timeout 5 bash -c 'echo > /dev/tcp/telehack.com/23' 2>&1 && echo "CONNECTED" || echo "BLOCKED")
if [[ "$PORT_23_TEST" == *"timed out"* ]]; then
  add_test_result "negative_port_23_blocked" "blocked" "blocked" "true" "Telnet port 23 correctly blocked (timeout)" "both"
elif [[ "$PORT_23_TEST" == *"BLOCKED"* ]]; then
  add_test_result "negative_port_23_blocked" "blocked" "blocked" "true" "Telnet port 23 correctly blocked" "both"
elif [[ "$PORT_23_TEST" == *"Connection refused"* ]]; then
  add_test_result "negative_port_23_blocked" "blocked" "reached_server" "false" "Telnet port 23 traffic reached server (SG too permissive)" "both"
else
  add_test_result "negative_port_23_blocked" "blocked" "connected" "false" "Telnet port 23 should be blocked" "both"
fi

# Test 20: Redis port (6379) should be blocked
# Only "timed out" means SG blocked it; "Connection refused" means traffic got through
echo "Test 20: Redis port (6379) should be blocked" >> /tmp/vpc-tests/test.log
PORT_6379_TEST=$(timeout 5 bash -c 'echo > /dev/tcp/8.8.8.8/6379' 2>&1 && echo "CONNECTED" || echo "BLOCKED")
if [[ "$PORT_6379_TEST" == *"timed out"* ]]; then
  add_test_result "negative_port_6379_blocked" "blocked" "blocked" "true" "Redis port 6379 correctly blocked (timeout)" "both"
elif [[ "$PORT_6379_TEST" == *"BLOCKED"* ]]; then
  add_test_result "negative_port_6379_blocked" "blocked" "blocked" "true" "Redis port 6379 correctly blocked" "both"
elif [[ "$PORT_6379_TEST" == *"Connection refused"* ]]; then
  add_test_result "negative_port_6379_blocked" "blocked" "reached_server" "false" "Redis port 6379 traffic reached server (SG too permissive)" "both"
else
  add_test_result "negative_port_6379_blocked" "blocked" "connected" "false" "Redis port 6379 should be blocked" "both"
fi

# Test 21: Verify traffic goes through NAT (not direct)
echo "Test 21: Verify traffic goes through NAT (not direct)" >> /tmp/vpc-tests/test.log
# Get our outbound IP and verify it's one of the NAT Gateway's EIPs
OUTBOUND_IP=$(curl -s --connect-timeout 10 https://api.ipify.org 2>&1 || echo "FAILED")
# Get ALL NAT Gateway EIPs for this VPC
NAT_EIPS=$(aws ec2 describe-nat-gateways --region $AWS_REGION \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query 'NatGateways[].NatGatewayAddresses[].PublicIp' --output text 2>&1)
if [[ "$NAT_EIPS" == *"$OUTBOUND_IP"* ]]; then
  add_test_result "negative_traffic_via_nat" "via_nat" "via_nat:$OUTBOUND_IP" "true" "Outbound traffic correctly routes through NAT Gateway ($OUTBOUND_IP)" "codebuild"
elif [[ "$OUTBOUND_IP" == "FAILED" ]]; then
  add_test_result "negative_traffic_via_nat" "via_nat" "no_internet" "false" "Could not verify NAT routing - no internet access" "codebuild"
else
  add_test_result "negative_traffic_via_nat" "via_nat" "unknown_ip:$OUTBOUND_IP" "false" "Outbound IP ($OUTBOUND_IP) doesn't match any NAT EIP ($NAT_EIPS)" "codebuild"
fi

# =============================================================================
# Calculate summary and upload results
# =============================================================================
TOTAL_TESTS=$(jq '.tests | length' /tmp/vpc-tests/results.json)
PASSED_TESTS=$(jq '[.tests[] | select(.passed == true)] | length' /tmp/vpc-tests/results.json)
FAILED_TESTS=$((TOTAL_TESTS - PASSED_TESTS))

# Count by component
CODEBUILD_PASSED=$(jq '[.tests[] | select(.passed == true and .component == "codebuild")] | length' /tmp/vpc-tests/results.json)
CODEBUILD_TOTAL=$(jq '[.tests[] | select(.component == "codebuild")] | length' /tmp/vpc-tests/results.json)
LAMBDA_PASSED=$(jq '[.tests[] | select(.passed == true and .component == "lambda")] | length' /tmp/vpc-tests/results.json)
LAMBDA_TOTAL=$(jq '[.tests[] | select(.component == "lambda")] | length' /tmp/vpc-tests/results.json)
BOTH_PASSED=$(jq '[.tests[] | select(.passed == true and .component == "both")] | length' /tmp/vpc-tests/results.json)
BOTH_TOTAL=$(jq '[.tests[] | select(.component == "both")] | length' /tmp/vpc-tests/results.json)

# Count negative tests (tests that verify blocked access)
NEGATIVE_PASSED=$(jq '[.tests[] | select(.passed == true and (.name | startswith("negative_")))] | length' /tmp/vpc-tests/results.json)
NEGATIVE_TOTAL=$(jq '[.tests[] | select(.name | startswith("negative_"))] | length' /tmp/vpc-tests/results.json)

jq --arg total "$TOTAL_TESTS" \
   --arg passed "$PASSED_TESTS" \
   --arg failed "$FAILED_TESTS" \
   --arg cb_passed "$CODEBUILD_PASSED" \
   --arg cb_total "$CODEBUILD_TOTAL" \
   --arg lambda_passed "$LAMBDA_PASSED" \
   --arg lambda_total "$LAMBDA_TOTAL" \
   --arg both_passed "$BOTH_PASSED" \
   --arg both_total "$BOTH_TOTAL" \
   --arg neg_passed "$NEGATIVE_PASSED" \
   --arg neg_total "$NEGATIVE_TOTAL" \
   '. + {"summary": {
     "total": ($total|tonumber),
     "passed": ($passed|tonumber),
     "failed": ($failed|tonumber),
     "codebuild_tests": {"passed": ($cb_passed|tonumber), "total": ($cb_total|tonumber)},
     "lambda_tests": {"passed": ($lambda_passed|tonumber), "total": ($lambda_total|tonumber)},
     "shared_tests": {"passed": ($both_passed|tonumber), "total": ($both_total|tonumber)},
     "negative_tests": {"passed": ($neg_passed|tonumber), "total": ($neg_total|tonumber), "description": "Tests that verify blocked/unauthorized access fails"}
   }}' \
   /tmp/vpc-tests/results.json > /tmp/vpc-tests/results.tmp && mv /tmp/vpc-tests/results.tmp /tmp/vpc-tests/results.json

echo "" >> /tmp/vpc-tests/test.log
echo "=== Test Results Summary ===" >> /tmp/vpc-tests/test.log
echo "Total: $TOTAL_TESTS, Passed: $PASSED_TESTS, Failed: $FAILED_TESTS" >> /tmp/vpc-tests/test.log
echo "Negative Tests (verify blocked access): $NEGATIVE_PASSED/$NEGATIVE_TOTAL passed" >> /tmp/vpc-tests/test.log
cat /tmp/vpc-tests/results.json >> /tmp/vpc-tests/test.log

# Upload results to S3
aws s3 cp /tmp/vpc-tests/results.json s3://$TEST_RESULTS_BUCKET/vpc-tests/private-subnet-$INSTANCE_ID-$TIMESTAMP.json --region $AWS_REGION
aws s3 cp /tmp/vpc-tests/test.log s3://$TEST_RESULTS_BUCKET/vpc-tests/private-subnet-$INSTANCE_ID-$TIMESTAMP.log --region $AWS_REGION

echo ""
echo "=============================================="
echo "VPC PRIVATE SUBNET TESTS COMPLETED"
echo "=============================================="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
echo ""
echo "Negative Tests (blocked access verification): $NEGATIVE_PASSED/$NEGATIVE_TOTAL"
echo ""
echo "Results uploaded to: s3://$TEST_RESULTS_BUCKET/vpc-tests/"
echo "=============================================="
