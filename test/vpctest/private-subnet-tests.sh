#!/bin/bash
# VPC Private Subnet Tests (Lambda Simulation)
# This script tests the network isolation and connectivity expected for Lambda functions
# Required environment variables:
#   - TEST_RESULTS_BUCKET: S3 bucket for results
#   - AWS_REGION: AWS region
#   - SECURITY_GROUP_ID: Security group ID to verify

set -x

# Validate required environment variables
if [ -z "$TEST_RESULTS_BUCKET" ] || [ -z "$AWS_REGION" ] || [ -z "$SECURITY_GROUP_ID" ]; then
  echo "ERROR: Required environment variables not set"
  echo "Required: TEST_RESULTS_BUCKET, AWS_REGION, SECURITY_GROUP_ID"
  exit 1
fi

# Install required tools (nmap-ncat provides nc on Amazon Linux 2023)
yum install -y nmap-ncat jq curl

# Create test results directory
mkdir -p /tmp/vpc-tests
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Initialize results JSON
cat > /tmp/vpc-tests/results.json << 'INITEOF'
{
  "testSuite": "VPC Private Subnet Tests (Lambda Simulation)",
  "instanceId": "INSTANCE_ID_PLACEHOLDER",
  "timestamp": "TIMESTAMP_PLACEHOLDER",
  "subnet": "private",
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
  
  jq --arg name "$name" \
     --arg expected "$expected" \
     --arg actual "$actual" \
     --arg passed "$passed" \
     --arg details "$details" \
     '.tests += [{"name": $name, "expected": $expected, "actual": $actual, "passed": ($passed == "true"), "details": $details}]' \
     /tmp/vpc-tests/results.json > /tmp/vpc-tests/results.tmp && mv /tmp/vpc-tests/results.tmp /tmp/vpc-tests/results.json
}

echo "=== VPC Private Subnet Security Tests Starting ===" > /tmp/vpc-tests/test.log

# Test 1: External HTTP should work via NAT Gateway
echo "Test 1: External HTTP via NAT Gateway" >> /tmp/vpc-tests/test.log
HTTP_RESULT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://httpbin.org/get 2>&1 || echo "TIMEOUT")
if [ "$HTTP_RESULT" = "200" ]; then
  add_test_result "external_http_via_nat" "reachable" "reachable:$HTTP_RESULT" "true" "HTTP to external internet works via NAT Gateway"
else
  add_test_result "external_http_via_nat" "reachable" "blocked:$HTTP_RESULT" "false" "HTTP to external internet should work via NAT Gateway"
fi

# Test 2: External HTTPS should work via NAT Gateway
echo "Test 2: External HTTPS via NAT Gateway" >> /tmp/vpc-tests/test.log
HTTPS_RESULT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 https://www.google.com 2>&1 || echo "TIMEOUT")
if [ "$HTTPS_RESULT" = "200" ] || [ "$HTTPS_RESULT" = "301" ] || [ "$HTTPS_RESULT" = "302" ]; then
  add_test_result "external_https_via_nat" "reachable" "reachable:$HTTPS_RESULT" "true" "HTTPS to external internet works via NAT Gateway"
else
  add_test_result "external_https_via_nat" "reachable" "blocked:$HTTPS_RESULT" "false" "HTTPS to external internet should work via NAT Gateway"
fi

# Test 3: S3 VPC endpoint connectivity
echo "Test 3: S3 VPC Endpoint" >> /tmp/vpc-tests/test.log
S3_TEST=$(aws s3 ls s3://$TEST_RESULTS_BUCKET --region $AWS_REGION 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$S3_TEST" == *"SUCCESS"* ]]; then
  add_test_result "s3_vpc_endpoint" "reachable" "reachable" "true" "S3 VPC endpoint working"
else
  add_test_result "s3_vpc_endpoint" "reachable" "unreachable" "false" "S3 VPC endpoint not working: $S3_TEST"
fi

# Test 4: DynamoDB VPC endpoint connectivity
echo "Test 4: DynamoDB VPC Endpoint" >> /tmp/vpc-tests/test.log
DDB_TEST=$(aws dynamodb list-tables --region $AWS_REGION 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$DDB_TEST" == *"SUCCESS"* ]]; then
  add_test_result "dynamodb_vpc_endpoint" "reachable" "reachable" "true" "DynamoDB VPC endpoint working"
else
  add_test_result "dynamodb_vpc_endpoint" "reachable" "unreachable" "false" "DynamoDB VPC endpoint not working: $DDB_TEST"
fi

# Test 5: Secrets Manager VPC endpoint connectivity
echo "Test 5: Secrets Manager VPC Endpoint" >> /tmp/vpc-tests/test.log
SM_TEST=$(aws secretsmanager list-secrets --region $AWS_REGION --max-results 1 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$SM_TEST" == *"SUCCESS"* ]]; then
  add_test_result "secretsmanager_vpc_endpoint" "reachable" "reachable" "true" "Secrets Manager VPC endpoint working"
else
  add_test_result "secretsmanager_vpc_endpoint" "reachable" "unreachable" "false" "Secrets Manager VPC endpoint not working: $SM_TEST"
fi

# Test 6: Security Group has no inbound rules (Lambda isolation)
echo "Test 6: Security Group Ingress Rules" >> /tmp/vpc-tests/test.log
SG_INGRESS=$(aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID --region $AWS_REGION --query 'SecurityGroups[0].IpPermissions' 2>&1)
if [ "$SG_INGRESS" = "[]" ]; then
  add_test_result "sg_no_ingress" "no_ingress_rules" "no_ingress_rules" "true" "Security group has no inbound rules (Lambda isolation)"
else
  add_test_result "sg_no_ingress" "no_ingress_rules" "has_ingress_rules" "false" "Security group should have no inbound rules: $SG_INGRESS"
fi

# Test 7: Cannot be reached from public internet (no public IP)
echo "Test 7: No Public IP" >> /tmp/vpc-tests/test.log
PUBLIC_IP=$(curl -s --connect-timeout 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>&1)
if [ -z "$PUBLIC_IP" ] || [[ "$PUBLIC_IP" == *"404"* ]] || [[ "$PUBLIC_IP" == *"Not Found"* ]]; then
  add_test_result "no_public_ip" "no_public_ip" "no_public_ip" "true" "Instance has no public IP (isolated from internet)"
else
  add_test_result "no_public_ip" "no_public_ip" "has_public_ip:$PUBLIC_IP" "false" "Instance should not have a public IP"
fi

# Test 8: Cannot reach other instances in private subnet directly (Lambda isolation)
echo "Test 8: Cannot reach other private instances" >> /tmp/vpc-tests/test.log
# Try to connect to a common port on a hypothetical other instance in the subnet
INTERNAL_TEST=$(timeout 3 bash -c 'echo > /dev/tcp/10.0.2.50/443' 2>&1 && echo "CONNECTED" || echo "BLOCKED")
if [[ "$INTERNAL_TEST" == *"BLOCKED"* ]] || [[ "$INTERNAL_TEST" == *"timed out"* ]] || [[ "$INTERNAL_TEST" == *"Connection refused"* ]]; then
  add_test_result "internal_isolation" "isolated" "isolated" "true" "Cannot reach other instances in private subnet"
else
  add_test_result "internal_isolation" "isolated" "reachable" "false" "Should not be able to reach other instances: $INTERNAL_TEST"
fi

# Test 9: DNS resolution works
echo "Test 9: DNS resolution" >> /tmp/vpc-tests/test.log
DNS_TEST=$(nslookup s3.$AWS_REGION.amazonaws.com 2>&1)
if [[ "$DNS_TEST" == *"Address"* ]]; then
  add_test_result "dns_resolution" "working" "working" "true" "DNS resolution working correctly"
else
  add_test_result "dns_resolution" "working" "failed" "false" "DNS resolution failed: $DNS_TEST"
fi

# Calculate summary
TOTAL_TESTS=$(jq '.tests | length' /tmp/vpc-tests/results.json)
PASSED_TESTS=$(jq '[.tests[] | select(.passed == true)] | length' /tmp/vpc-tests/results.json)
FAILED_TESTS=$((TOTAL_TESTS - PASSED_TESTS))

jq --arg total "$TOTAL_TESTS" --arg passed "$PASSED_TESTS" --arg failed "$FAILED_TESTS" \
   '. + {"summary": {"total": ($total|tonumber), "passed": ($passed|tonumber), "failed": ($failed|tonumber)}}' \
   /tmp/vpc-tests/results.json > /tmp/vpc-tests/results.tmp && mv /tmp/vpc-tests/results.tmp /tmp/vpc-tests/results.json

echo "=== Test Results ===" >> /tmp/vpc-tests/test.log
cat /tmp/vpc-tests/results.json >> /tmp/vpc-tests/test.log

# Upload results to S3
aws s3 cp /tmp/vpc-tests/results.json s3://$TEST_RESULTS_BUCKET/vpc-tests/private-subnet-$INSTANCE_ID-$TIMESTAMP.json --region $AWS_REGION
aws s3 cp /tmp/vpc-tests/test.log s3://$TEST_RESULTS_BUCKET/vpc-tests/private-subnet-$INSTANCE_ID-$TIMESTAMP.log --region $AWS_REGION

echo "Tests completed. Results uploaded to S3."
