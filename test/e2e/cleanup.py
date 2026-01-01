"""
Cleanup script for E2E tests.
Run this to clean up any orphaned AWS resources after test failures.
"""

import os
import boto3
from datetime import datetime, timedelta


AWS_REGION = os.environ.get("AWS_REGION", "eu-west-3")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "gits-jobs")
TEST_GITHUB_EMAIL = os.environ.get("TEST_GITHUB_EMAIL", "")


def cleanup_test_resources():
    """Clean up any orphaned test resources."""
    if not TEST_GITHUB_EMAIL:
        print("TEST_GITHUB_EMAIL not set, skipping cleanup")
        return
    
    dynamodb = boto3.client("dynamodb", region_name=AWS_REGION)
    events = boto3.client("events", region_name=AWS_REGION)
    
    print(f"Cleaning up resources for user: {TEST_GITHUB_EMAIL}")
    
    # Query all jobs for test user
    try:
        response = dynamodb.query(
            TableName=DYNAMODB_TABLE,
            KeyConditionExpression="user_id = :uid",
            ExpressionAttributeValues={
                ":uid": {"S": TEST_GITHUB_EMAIL}
            }
        )
        
        jobs = response.get("Items", [])
        print(f"Found {len(jobs)} jobs to clean up")
        
        for job in jobs:
            job_id = job["job_id"]["S"]
            status = job.get("status", {}).get("S", "unknown")
            added_at = job.get("added_at", {}).get("N", "0")
            
            print(f"Processing job {job_id} (status: {status})")
            
            # Delete EventBridge rule if it exists
            if status == "pending":
                try:
                    # Remove targets first
                    events.remove_targets(
                        Rule=job_id,
                        Ids=["Target1"],
                        Force=True
                    )
                    print(f"  Removed targets for rule {job_id}")
                except Exception as e:
                    print(f"  Could not remove targets: {e}")
                
                try:
                    # Delete the rule
                    events.delete_rule(
                        Name=job_id,
                        Force=True
                    )
                    print(f"  Deleted EventBridge rule {job_id}")
                except Exception as e:
                    print(f"  Could not delete rule: {e}")
            
            # Delete DynamoDB item
            try:
                dynamodb.delete_item(
                    TableName=DYNAMODB_TABLE,
                    Key={
                        "user_id": {"S": TEST_GITHUB_EMAIL},
                        "added_at": {"N": added_at}
                    }
                )
                print(f"  Deleted DynamoDB item for {job_id}")
            except Exception as e:
                print(f"  Could not delete DynamoDB item: {e}")
        
        print("Cleanup complete!")
        
    except Exception as e:
        print(f"Error during cleanup: {e}")


def cleanup_old_eventbridge_rules():
    """Clean up old gits- EventBridge rules that may be orphaned."""
    events = boto3.client("events", region_name=AWS_REGION)
    
    try:
        # List all rules with gits- prefix
        response = events.list_rules(NamePrefix="gits-")
        rules = response.get("Rules", [])
        
        print(f"Found {len(rules)} gits- rules")
        
        # Clean up rules older than 1 hour
        cutoff = datetime.now() - timedelta(hours=1)
        
        for rule in rules:
            rule_name = rule["Name"]
            
            # Extract timestamp from rule name (format: gits-<timestamp>)
            try:
                timestamp = int(rule_name.split("-")[1])
                rule_time = datetime.fromtimestamp(timestamp)
                
                if rule_time < cutoff:
                    print(f"Cleaning up old rule: {rule_name}")
                    
                    # Remove targets
                    try:
                        events.remove_targets(
                            Rule=rule_name,
                            Ids=["Target1"],
                            Force=True
                        )
                    except:
                        pass
                    
                    # Delete rule
                    events.delete_rule(Name=rule_name, Force=True)
                    print(f"  Deleted {rule_name}")
                    
            except (IndexError, ValueError):
                continue
                
    except Exception as e:
        print(f"Error cleaning up EventBridge rules: {e}")


if __name__ == "__main__":
    cleanup_test_resources()
    cleanup_old_eventbridge_rules()
