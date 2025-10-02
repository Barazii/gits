"""Lambda handler for gits proxy.

This function receives (via API Gateway) a JSON payload containing:
  schedule_time: ISO 8601 timestamp (UTC, may end with Z)
  repo_url: HTTPS Git repository URL
  zip_filename: Name of the zip file (string)
  zip_base64: Base64-encoded content of the zip containing modified files
  github_token_secret: Name of the GitHub token secret in Secrets Manager

Environment variables expected (configure on the Lambda function):
  AWS_REGION                (implicit in Lambda but read for safety)
  AWS_BUCKET_NAME           Target S3 bucket for temporary storage
  AWS_CODEBUILD_PROJECT_NAME Name of CodeBuild project to trigger later via EventBridge
  AWS_ACCOUNT_ID            (used to build ARNs if needed)
  EVENTBRIDGE_TARGET_ROLE_ARN  (Role ARN EventBridge assumes to start CodeBuild)

The handler will:
  1. Validate and parse schedule_time (must be in future)
  2. Decode and upload the zip to s3://<bucket>/<prefix>/<zip_filename>
  3. Create an EventBridge rule with cron expression matching schedule_time
  4. Attach CodeBuild project as a target with environment overrides (S3_PATH, REPO_URL, GITHUB_TOKEN_SECRET)
  5. Return JSON with rule_name, s3_path, cron_expression

No external dependencies beyond boto3 (available by default in Lambda)."""

from __future__ import annotations

import base64
import json
import os
import re
from datetime import datetime, timezone
import time
from typing import Any, Dict
import logging
import boto3


logger = logging.getLogger()
logger.setLevel(logging.INFO)

_ISO_RE = re.compile(
    r"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.\d+)?(Z|[+-][0-9]{2}:[0-9]{2})?$"
)


def _parse_iso8601(ts: str) -> datetime:
    if not _ISO_RE.match(ts):
        raise ValueError("Invalid ISO 8601 timestamp format")
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    # Python 3.11: fromisoformat supports offset
    dt = datetime.fromisoformat(ts)
    if dt.tzinfo is None:
        # Assume UTC if naive
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _future_guard(dt_utc: datetime) -> None:
    now = datetime.now(timezone.utc)
    if dt_utc <= now:
        raise ValueError("schedule_time must be in the future")


def _cron_expression(dt_utc: datetime) -> str:
    # cron(M H d m ? Y)
    return f"{dt_utc.minute} {dt_utc.hour} {dt_utc.day} {dt_utc.month} ? {dt_utc.year}"


def _response(status: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {"statusCode": status, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}


def lambda_handler(event, context):
    logger.info("Invocation start")
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

        missing = [k for k, v in [
            ("schedule_time", schedule_time),
            ("repo_url", repo_url),
            ("zip_filename", zip_filename),
            ("zip_base64", zip_b64),
            ("github_token_secret", github_token_secret),
        ] if not v]
        if missing:
            return _response(400, {"error": f"Missing required fields: {', '.join(missing)}"})

        try:
            dt_utc = _parse_iso8601(schedule_time)
            _future_guard(dt_utc)
        except ValueError as e:
            return _response(400, {"error": str(e)})

        region = os.environ.get("AWS_APP_REGION") or os.environ.get("AWS_DEFAULT_REGION")
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
