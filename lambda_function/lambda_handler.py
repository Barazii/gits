"""Lambda handler for gits proxy.

This function receives (via API Gateway) a JSON payload containing:
  schedule_time: ISO 8601 timestamp UTC ends with Z
  repo_url: HTTPS Git repository URL
  zip_filename: Name of the zip file (string)
  zip_base64: Base64-encoded content of the zip containing modified files
  github_token_secret: Name of the GitHub token secret in Secrets Manager. """


import base64
import json
import os
from datetime import datetime, timezone
import time
from typing import Any, Dict
import logging
import boto3


logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _parse_iso8601(ts: str) -> datetime:
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    dt = datetime.fromisoformat(ts)
    if dt.tzinfo is None:
        # Assume UTC if naive
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _cron_expression(dt_utc: datetime) -> str:
    # cron(M H d m ? Y)
    return f"{dt_utc.minute} {dt_utc.hour} {dt_utc.day} {dt_utc.month} ? {dt_utc.year}"


def _response(status: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {"statusCode": status, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}


def lambda_handler(event, context):
    logger.info(f"Raw event keys: {list(event.keys())}")
    try:
        if "body" in event:
            logger.info("Body key found.")
            body_raw = event["body"]
            if event.get("isBase64Encoded"):
                logger.info("Message is base64 encoded.")
                body_raw = base64.b64decode(body_raw).decode()
            data = json.loads(body_raw or "{}")
        else:
            data = event or {}

        schedule_time = data.get("schedule_time")
        repo_url = data.get("repo_url")
        zip_filename = data.get("zip_filename")
        zip_b64 = data.get("zip_base64")
        github_token_secret = data.get("github_token_secret")
        github_user = data.get("github_user")
        github_email = data.get("github_email")

        try:
            dt_utc = _parse_iso8601(schedule_time)
        except ValueError as e:
            return _response(400, {"error": str(e)})

        region = os.environ.get("AWS_APP_REGION")
        bucket = os.environ["AWS_BUCKET_NAME"]
        project = os.environ["AWS_CODEBUILD_PROJECT_NAME"]
        account_id = os.environ.get("AWS_ACCOUNT_ID")
        target_role_arn = os.environ.get("EVENTBRIDGE_TARGET_ROLE_ARN")

        s3_client = boto3.client("s3", region_name=region)
        events_client = boto3.client("events", region_name=region)

        # Prepare S3 key
        prefix = f"changes-{int(time.time())}"
        key = f"{prefix}/{zip_filename}"

        try:
            zip_bytes = base64.b64decode(zip_b64)
        except Exception:
            return _response(400, {"error": "zip_base64 is not valid base64"})

        # Upload to S3
        s3_client.put_object(Bucket=bucket, Key=key, Body=zip_bytes)
        s3_path = f"s3://{bucket}/{key}"

        cron_expr = _cron_expression(dt_utc)
        rule_name = f"gits-{int(time.time())}"

        events_client.put_rule(
            Name=rule_name,
            ScheduleExpression=f"cron({cron_expr})",
            State="ENABLED",
        )

        cb_project_arn = f"arn:aws:codebuild:{region}:{account_id}:project/{project}"

        input_payload = {
            "environmentVariablesOverride": [
                {"name": "S3_PATH", "value": s3_path, "type": "PLAINTEXT"},
                {"name": "REPO_URL", "value": repo_url, "type": "PLAINTEXT"},
                {"name": "GITHUB_TOKEN_SECRET", "value": github_token_secret, "type": "PLAINTEXT"},
                {"name": "GITHUB_USER", "value": github_user, "type": "PLAINTEXT"},
                {"name": "GITHUB_EMAIL", "value": github_email, "type": "PLAINTEXT"}
            ]
        }

        target_def: Dict[str, Any] = {
            "Id": "Target1",
            "Arn": cb_project_arn,
            "Input": json.dumps(input_payload),
            "RoleArn": target_role_arn,
        }

        events_client.put_targets(Rule=rule_name, Targets=[target_def])

        return _response(200, {
            "message": "Scheduled",
            "rule_name": rule_name,
            "cron_expression": cron_expr,
            "s3_path": s3_path,
        })

    except Exception as e:
        return _response(500, {"error": str(e)})
