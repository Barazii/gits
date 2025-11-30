# gits CloudFormation Stacks

Modular infrastructure as separate stacks without nested/S3 hosted templates. Deploy stacks in order using direct file references.

## Stacks
1. `ecr.yaml` – ECR repositories for the four Lambda container images
2. `s3.yaml` – S3 artifact bucket (encryption, optional versioning, public access blocked)
3. `dynamodb.yaml` – DynamoDB jobs table (PK user_id, SK added_at, GSI job_id-index)
4. `iam.yaml` – IAM roles (Lambda execution, EventBridge target role, CodeBuild service role)
5. `github-secret.yaml` – Secrets Manager secret for GitHub OAuth token
6. `codebuild.yaml` – CodeBuild project (imports CodeBuild service role and GitHub secret ARNs)
7. `lambdas.yaml` – Four container-image Lambdas (imports lambda execution role + EventBridge target role)
8. `eventbridge.yaml` – Build state change rule (imports codebuild lens lambda ARN)
9. `apigateway.yaml` – API Gateway REST API with endpoints for the schedule, delete, and status Lambdas

## Exports
Each stack exports ARNs or names used by later stacks. Override export names via parameters if needed.

## Parameters Summary
See each template header. Common ones:
- ProjectName
- DynamoTableName / TableName
- ArtifactBucketName / BucketName
- ImageUri* (for each lambda)
- ECR encryption, mutability, scan settings

## Deploy Order & Commands
Assuming you are in repository root and have AWS credentials configured.

```bash
# 1. ECR Repositories
aws cloudformation deploy \
  --stack-name gits-ecr \
  --template-file cloudformation/ecr.yaml \
  --region eu-west-3 \
  --parameter-overrides ProjectName=gits ImageTagMutability=MUTABLE ScanOnPush=true EncryptionType=AES256

# 2. S3 Bucket
aws cloudformation deploy \
  --stack-name gits-s3 \
  --template-file cloudformation/s3.yaml \
  --region eu-west-3 \
  --parameter-overrides BucketName=gits-artifacts EnableVersioning=true BlockPublicAccess=true RetainOnDelete=false

# 3. DynamoDB Table
aws cloudformation deploy \
  --stack-name gits-dynamodb \
  --template-file cloudformation/dynamodb.yaml \
  --region eu-west-3 \
  --parameter-overrides TableName=gits-jobs PointInTimeRecovery=ENABLED BillingMode=PAY_PER_REQUEST

# 4. IAM
aws cloudformation deploy \
  --stack-name gits-iam \
  --template-file cloudformation/iam.yaml \
  --region eu-west-3 \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ProjectName=gits DynamoTableName=gits-jobs ArtifactBucketName=gits-artifacts

# 5. Secret Manager
aws cloudformation deploy \
  --stack-name gits-secret-manager \
  --template-file cloudformation/secretmanager.yaml \
  --region eu-west-3 \
  --parameter-overrides ProjectName=gits

# 6. CodeBuild
aws cloudformation deploy \
  --stack-name gits-codebuild \
  --template-file cloudformation/codebuild.yaml \
  --region eu-west-3 \
  --parameter-overrides ProjectName=gits ArtifactBucketName=gits-artifacts

# 7. Lambdas (provide built image URIs)
# Build and push your images to the ECR repos created earlier, then pass their Image URIs:
aws cloudformation deploy \
  --stack-name gits-lambdas \
  --template-file cloudformation/lambdas.yaml \
  --region eu-west-3 \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides ProjectName=gits DynamoTableName=gits-jobs ArtifactBucketName=gits-artifacts CodeBuildProjectName=gits \
    ImageUriSchedule=482497089777.dkr.ecr.eu-west-3.amazonaws.com/gits-schedule-lambda:latest \
    ImageUriDelete=482497089777.dkr.ecr.eu-west-3.amazonaws.com/gits-delete-lambda:latest \
    ImageUriStatus=482497089777.dkr.ecr.eu-west-3.amazonaws.com/gits-status-lambda:latest \
    ImageUriCodeBuildLens=482497089777.dkr.ecr.eu-west-3.amazonaws.com/gits-codebuildlens-lambda:latest

# 8. EventBridge
aws cloudformation deploy \
  --stack-name gits-events \
  --template-file cloudformation/eventbridge.yaml \
  --region eu-west-3 \
  --parameter-overrides ProjectName=gits

# 9. API Gateway
aws cloudformation deploy \
  --stack-name gits-apigateway \
  --template-file cloudformation/apigateway.yaml \
  --region eu-west-3 \
  --parameter-overrides ProjectName=gits
```

## Notes
- Templates use exports/imports; ensure unique export names in your account.
- No nested stacks; deploy independently. Rollback isolation per stack.
- Add alarms/log groups templates separately if required.
- ECR outputs export repo URIs to help reference/push; images must be built/pushed before deploying Lambdas.

## Cleanup
Delete in reverse order: apigateway -> events -> lambdas -> codebuild -> github-secret -> iam -> dynamodb -> s3 -> ecr.
