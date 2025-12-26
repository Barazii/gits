#!/bin/bash
# VPC Public Subnet Tests (CodeBuild Simulation)
# This script tests the network connectivity expected for CodeBuild
# Required environment variables:
#   - TEST_RESULTS_BUCKET: S3 bucket for results
#   - AWS_REGION: AWS region

set -x

# Validate required environment variables
if [ -z "$TEST_RESULTS_BUCKET" ] || [ -z "$AWS_REGION" ]; then
  echo "ERROR: Required environment variables not set"
  echo "Required: TEST_RESULTS_BUCKET, AWS_REGION"
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
  "testSuite": "VPC Public Subnet Tests (CodeBuild Simulation)",
  "instanceId": "INSTANCE_ID_PLACEHOLDER",
  "timestamp": "TIMESTAMP_PLACEHOLDER",
  "subnet": "public",
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

echo "=== VPC Public Subnet Security Tests Starting ===" > /tmp/vpc-tests/test.log

# Test 1: External HTTP should work (CodeBuild needs git clone)
echo "Test 1: External HTTP connectivity (should work for CodeBuild)" >> /tmp/vpc-tests/test.log
HTTP_RESULT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://httpbin.org/get 2>&1 || echo "TIMEOUT")
if [ "$HTTP_RESULT" = "200" ]; then
  add_test_result "external_http" "reachable" "reachable:$HTTP_RESULT" "true" "HTTP to external internet works"
else
  add_test_result "external_http" "reachable" "blocked:$HTTP_RESULT" "false" "HTTP to external internet should work for CodeBuild"
fi

# Test 2: External HTTPS should work
echo "Test 2: External HTTPS connectivity" >> /tmp/vpc-tests/test.log
HTTPS_RESULT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 https://github.com 2>&1 || echo "TIMEOUT")
if [ "$HTTPS_RESULT" = "200" ] || [ "$HTTPS_RESULT" = "301" ] || [ "$HTTPS_RESULT" = "302" ]; then
  add_test_result "external_https_github" "reachable" "reachable:$HTTPS_RESULT" "true" "HTTPS to GitHub works (required for git clone)"
else
  add_test_result "external_https_github" "reachable" "blocked:$HTTPS_RESULT" "false" "HTTPS to GitHub should work for CodeBuild"
fi

# Test 3: SSH port reachable (git clone over SSH)
echo "Test 3: SSH connectivity to GitHub" >> /tmp/vpc-tests/test.log
SSH_TEST=$(timeout 5 bash -c 'echo > /dev/tcp/github.com/22' 2>&1 && echo "CONNECTED" || echo "BLOCKED")
if [[ "$SSH_TEST" == *"CONNECTED"* ]]; then
  add_test_result "ssh_github" "reachable" "reachable" "true" "SSH to GitHub works (required for git clone over SSH)"
else
  add_test_result "ssh_github" "reachable" "blocked" "false" "SSH to GitHub should work: $SSH_TEST"
fi

# Test 4: AWS S3 endpoint reachability
echo "Test 4: S3 connectivity" >> /tmp/vpc-tests/test.log
S3_TEST=$(aws s3 ls s3://$TEST_RESULTS_BUCKET --region $AWS_REGION 2>&1 && echo "SUCCESS" || echo "FAILED")
if [[ "$S3_TEST" == *"SUCCESS"* ]]; then
  add_test_result "s3_access" "reachable" "reachable" "true" "S3 access working"
else
  add_test_result "s3_access" "reachable" "unreachable" "false" "S3 access not working: $S3_TEST"
fi

# Test 5: Cannot reach private subnet IPs directly (isolation)
echo "Test 5: Cannot reach private subnet directly" >> /tmp/vpc-tests/test.log
PRIVATE_TEST=$(timeout 3 bash -c 'echo > /dev/tcp/10.0.2.50/443' 2>&1 && echo "CONNECTED" || echo "BLOCKED")
if [[ "$PRIVATE_TEST" == *"BLOCKED"* ]] || [[ "$PRIVATE_TEST" == *"timed out"* ]] || [[ "$PRIVATE_TEST" == *"Connection refused"* ]]; then
  add_test_result "private_subnet_isolation" "isolated" "isolated" "true" "Cannot directly reach private subnet IPs"
else
  add_test_result "private_subnet_isolation" "isolated" "reachable" "false" "Should not reach private subnet: $PRIVATE_TEST"
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
aws s3 cp /tmp/vpc-tests/results.json s3://$TEST_RESULTS_BUCKET/vpc-tests/public-subnet-$INSTANCE_ID-$TIMESTAMP.json --region $AWS_REGION
aws s3 cp /tmp/vpc-tests/test.log s3://$TEST_RESULTS_BUCKET/vpc-tests/public-subnet-$INSTANCE_ID-$TIMESTAMP.log --region $AWS_REGION

echo "Tests completed. Results uploaded to S3."
