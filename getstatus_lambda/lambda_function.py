import base64
import boto3
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to retrieve the latest scheduled job status for a user.
    Queries DynamoDB for the most recent item by user_id, ordered by added_at descending.
    Returns schedule_time and status.
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        # Extract user_id from event (assuming it's passed in the body or directly)
        if 'body' in event:
            if event.get('isBase64Encoded'):
                body = json.loads(base64.b64decode(event['body']).decode())
            else:
                body = json.loads(event['body'])
            user_id = body.get('user_id')
        else:
            user_id = event.get('user_id')

        if not user_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'user_id is required'})
            }

        # Get DynamoDB table
        region = os.environ.get('AWS_APP_REGION', 'eu-north-1')
        table_name = os.environ.get('DYNAMODB_TABLE')
        if not table_name:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'DYNAMODB_TABLE environment variable not set'})
            }

        dynamodb = boto3.resource('dynamodb', region_name=region)
        table = dynamodb.Table(table_name)

        # Query for the most recent item by user_id (assuming added_at is sort key)
        response = table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('user_id').eq(user_id),
            ScanIndexForward=False,  # Descending order to get most recent
            Limit=1
        )

        if not response['Items']:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'No scheduled jobs found for this user'})
            }

        item = response['Items'][0]
        schedule_time = item.get('schedule_time')
        status = item.get('status')

        return {
            'statusCode': 200,
            'body': json.dumps({
                'schedule_time': schedule_time,
                'status': status
            })
        }

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }
