import boto3
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function triggered by CodeBuild job status changes.
    Collects build info and stores in DynamoDB.
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")

        # Extract build details from EventBridge event
        detail = event.get('detail', {})
        build_id = detail.get('build-id')
        build_status = detail.get('build-status')

        if not build_id or not build_status:
            logger.error("Missing build-id or build-status in event")
            return {'statusCode': 400, 'body': 'Invalid event'}

        # Get build details including environment variables
        codebuild_client = boto3.client('codebuild')
        response = codebuild_client.batch_get_builds(ids=[build_id])

        if not response['builds']:
            logger.error(f"No build found for id: {build_id}")
            return {'statusCode': 404, 'body': 'Build not found'}

        build = response['builds'][0]
        env_vars = build.get('environment', {}).get('environmentVariables', [])

        # Extract user_id from environment variables
        user_id = None
        for var in env_vars:
            if var['name'] == 'USER_ID':
                user_id = var['value']
                break

        if not user_id:
            logger.error("USER_ID not found in build environment variables")
            return {'statusCode': 400, 'body': 'USER_ID not found'}

        # Store in DynamoDB
        dynamodb = boto3.resource('dynamodb')
        table_name = os.environ.get('DYNAMODB_TABLE')
        if not table_name:
            logger.error("DYNAMODB_TABLE environment variable not set")
            return {'statusCode': 500, 'body': 'Configuration error'}

        table = dynamodb.Table(table_name)
        table.put_item(Item={
            'user_id': user_id,
            'build_id': build_id,
            'build_status': build_status
        })

        logger.info(f"Stored build info for user {user_id}: build_id={build_id}, status={build_status}")
        return {'statusCode': 200, 'body': 'Success'}

    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {'statusCode': 500, 'body': 'Internal error'}
