import boto3
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to delete a scheduled job.
    Deletes the EventBridge rule and the DynamoDB item.
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        # Assuming event is from API Gateway, body contains job_id and user_id
        body_raw = event.get("body", "{}")
        if event.get("isBase64Encoded"):
            import base64
            body_raw = base64.b64decode(body_raw).decode()
        data = json.loads(body_raw)
        job_id = data.get("job_id")
        user_id = data.get("user_id")

        if not job_id or not user_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'job_id and user_id are required'})
            }

        region = os.environ.get('AWS_APP_REGION', 'eu-north-1')
        table_name = os.environ.get('DYNAMODB_TABLE')
        if not table_name:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'DYNAMODB_TABLE environment variable not set'})
            }

        events_client = boto3.client("events", region_name=region)
        dynamodb = boto3.resource('dynamodb', region_name=region)
        table = dynamodb.Table(table_name)

        # Delete EventBridge rule
        try:
            # First remove targets, then delete the rule
            events_client.remove_targets(Rule=job_id, Ids=['Target1'], Force=True)
            events_client.delete_rule(Name=job_id, Force=True)
            logger.info(f"Deleted EventBridge rule: {job_id}")
        except events_client.exceptions.ResourceNotFoundException:
            logger.warning(f"Rule {job_id} not found")
        except Exception as e:
            logger.error(f"Error deleting rule: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': f'Failed to delete EventBridge rule: {str(e)}'})
            }

        # Delete DynamoDB item
        try:
            # Query to find the item with matching job_id
            response = table.query(
                KeyConditionExpression=boto3.dynamodb.conditions.Key('user_id').eq(user_id),
                FilterExpression=boto3.dynamodb.conditions.Attr('job_id').eq(job_id)
            )
            if not response['Items']:
                return {
                    'statusCode': 404,
                    'body': json.dumps({'error': 'Job not found'})
                }
            item = response['Items'][0]
            added_at = item['added_at']
            table.delete_item(Key={'user_id': user_id, 'added_at': added_at})
            logger.info(f"Deleted DynamoDB item: user_id={user_id}, job_id={job_id}")
        except Exception as e:
            logger.error(f"Error deleting DB item: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': f'Failed to delete DynamoDB item: {str(e)}'})
            }

        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Job deleted successfully'})
        }

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
