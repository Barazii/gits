# Gits Infrastructure - Terraform

This directory contains Terraform configuration to deploy the Gits infrastructure on AWS.

## Directory Structure

```
terraform/
├── main.tf                 # Main configuration, module calls
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── providers.tf            # Provider configuration
├── versions.tf             # Terraform and provider versions
├── backend.tf              # Backend configuration (state storage)
├── terraform.tfvars.example # Example variable values
├── modules/                # Terraform modules
│   ├── vpc/               # VPC, subnets, NAT, endpoints, security groups
│   ├── iam/               # IAM roles and policies
│   ├── dynamodb/          # DynamoDB table
│   ├── s3/                # S3 artifact bucket
│   ├── ecr/               # ECR repositories
│   ├── lambda/            # Lambda functions
│   ├── apigateway/        # API Gateway
│   ├── codebuild/         # CodeBuild project
│   ├── eventbridge/       # EventBridge rules
│   └── secrets/           # Secrets Manager
└── scripts/               # Deployment automation scripts
    ├── init.sh            # Initialize Terraform
    ├── plan.sh            # Plan changes
    ├── deploy.sh          # Deploy base infrastructure
    ├── build-and-push-lambdas.sh  # Build and push Lambda images
    ├── deploy-lambdas.sh  # Deploy Lambda functions
    ├── deploy-all.sh      # Full deployment (all steps)
    ├── destroy.sh         # Destroy infrastructure
    ├── update-lambdas.sh  # Update Lambda code only
    └── output.sh          # Show outputs
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [Docker](https://www.docker.com/) for building Lambda images
- GitHub personal access token for private repository access

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform
./scripts/init.sh
```

### 2. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration
```

### 3. Set GitHub Token

```bash
export TF_VAR_github_token='your-github-token'
# Or add GITHUB_TOKEN=your-token to ~/.gits/config
```

### 4. Deploy Everything

```bash
./scripts/deploy-all.sh
```

Or deploy in steps:

```bash
# Deploy base infrastructure (VPC, IAM, ECR, etc.)
./scripts/deploy.sh

# Build and push Lambda container images
./scripts/build-and-push-lambdas.sh

# Deploy Lambda functions and remaining resources
./scripts/deploy-lambdas.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `init.sh` | Initialize Terraform, download providers |
| `plan.sh` | Show planned changes |
| `deploy.sh` | Deploy base infrastructure |
| `build-and-push-lambdas.sh` | Build and push Lambda container images to ECR |
| `deploy-lambdas.sh` | Deploy Lambda functions with image URIs |
| `deploy-all.sh` | Complete deployment (all steps) |
| `destroy.sh` | Destroy all infrastructure |
| `update-lambdas.sh` | Update Lambda function code only |
| `output.sh` | Show Terraform outputs |

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `github_token` | GitHub personal access token (set via `TF_VAR_github_token`) |

### Optional Variables

See `terraform.tfvars.example` for all configurable variables including:
- AWS region
- VPC CIDR ranges
- DynamoDB configuration
- Lambda memory/timeout settings
- API Gateway throttling

### Region-Specific Configuration

The `s3_prefix_list_id` and `dynamodb_prefix_list_id` variables are region-specific. Default values are for `eu-west-3` (Paris). Update these for your region.

## Remote State (Optional)

To enable remote state storage, uncomment and configure the backend in `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "gits/terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

## Differences from CloudFormation

This Terraform configuration replicates the CloudFormation stacks with the following improvements:

1. **Modular Structure**: Resources organized into reusable modules
2. **Variable Validation**: Input validation for configuration
3. **Conditional Resources**: Lambda/API Gateway only created when images available
4. **Better State Management**: Terraform state for change tracking
5. **Plan Before Apply**: Preview changes before deployment

## Outputs

After deployment, the following outputs are available:

- `vpc_id` - VPC ID
- `api_gateway_url` - API Gateway invoke URL
- `api_key_id` - API Key ID (retrieve value from AWS Console)
- `ecr_*_repo_url` - ECR repository URLs for Lambda images
- `*_lambda_arn` - Lambda function ARNs

View outputs:
```bash
./scripts/output.sh
# or
terraform output
```

## Troubleshooting

### Lambda images not found
Run `./scripts/build-and-push-lambdas.sh` before `./scripts/deploy-lambdas.sh`

### Permission errors
Ensure AWS credentials have sufficient permissions. The IAM module creates a deployment role similar to CloudFormation.

### State lock errors
If using remote state with DynamoDB locking, ensure the lock table exists.

## Cleanup

To destroy all resources:

```bash
./scripts/destroy.sh
```

**Warning**: This will delete all resources including data in DynamoDB and S3.
