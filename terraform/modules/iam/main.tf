#------------------------------------------------------------------------------
# Schedule Lambda Role
#------------------------------------------------------------------------------
resource "aws_iam_role" "schedule_lambda" {
  name = "${var.project_name}-schedule-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-schedule-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "schedule_lambda_basic" {
  role       = aws_iam_role.schedule_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "schedule_lambda" {
  name = "ScheduleLambdaAccess"
  role = aws_iam_role.schedule_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.dynamodb_table_name}"
      },
      {
        Sid    = "EventBridgeCreateRules"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:PutTargets",
          "events:DescribeRule"
        ]
        Resource = "arn:aws:events:${var.aws_region}:${var.account_id}:rule/*"
      },
      {
        Sid    = "S3PutObject"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${var.artifact_bucket_name}/*"
      },
      {
        Sid    = "SecretsManagerCreate"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:UpdateSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:*"
      },
      {
        Sid      = "PassRoleToEventBridge"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.eventbridge_target.arn
      },
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2NetworkInterface"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Delete Lambda Role
#------------------------------------------------------------------------------
resource "aws_iam_role" "delete_lambda" {
  name = "${var.project_name}-delete-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-delete-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "delete_lambda_basic" {
  role       = aws_iam_role.delete_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "delete_lambda" {
  name = "DeleteLambdaAccess"
  role = aws_iam_role.delete_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoReadDelete"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.dynamodb_table_name}"
      },
      {
        Sid    = "EventBridgeDeleteRules"
        Effect = "Allow"
        Action = [
          "events:RemoveTargets",
          "events:DeleteRule",
          "events:DescribeRule"
        ]
        Resource = "arn:aws:events:${var.aws_region}:${var.account_id}:rule/*"
      },
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2NetworkInterface"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Status Lambda Role
#------------------------------------------------------------------------------
resource "aws_iam_role" "status_lambda" {
  name = "${var.project_name}-status-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-status-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "status_lambda_basic" {
  role       = aws_iam_role.status_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "status_lambda" {
  name = "StatusLambdaAccess"
  role = aws_iam_role.status_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoQuery"
        Effect = "Allow"
        Action = [
          "dynamodb:Query"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.dynamodb_table_name}"
      },
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2NetworkInterface"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CodeBuildLens Lambda Role
#------------------------------------------------------------------------------
resource "aws_iam_role" "codebuildlens_lambda" {
  name = "${var.project_name}-codebuildlens-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-codebuildlens-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "codebuildlens_lambda_basic" {
  role       = aws_iam_role.codebuildlens_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "codebuildlens_lambda" {
  name = "CodeBuildLensLambdaAccess"
  role = aws_iam_role.codebuildlens_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeBuildRead"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:ListProjects"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoQuery"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.dynamodb_table_name}"
      },
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2NetworkInterface"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# EventBridge Target Role
#------------------------------------------------------------------------------
resource "aws_iam_role" "eventbridge_target" {
  name = "${var.project_name}-events-target"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-events-target"
  }
}

resource "aws_iam_role_policy" "eventbridge_target" {
  name = "AllowStartCodeBuild"
  role = aws_iam_role.eventbridge_target.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "codebuild:StartBuild"
        Resource = "arn:aws:codebuild:${var.aws_region}:${var.account_id}:project/${var.project_name}"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CodeBuild Service Role
#------------------------------------------------------------------------------
resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-codebuild-role"
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name = "CodeBuildSecretsS3Logs"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CodeBuild"
        Effect   = "Allow"
        Action   = "codebuild:*"
        Resource = "*"
      },
      {
        Sid    = "S3ReadArtifacts"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${var.artifact_bucket_name}/*"
      },
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:CreateSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeDhcpOptions",
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# VPC Flow Logs Role
#------------------------------------------------------------------------------
resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.project_name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-vpc-flow-logs-role"
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "FlowLogsPolicy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/vpc/${var.project_name}-flow-logs:*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CloudFormation Deployment Role
# NOTE: This role is created by the bootstrap-iam.sh script before Terraform runs.
# We use a data source to reference it instead of creating it.
#------------------------------------------------------------------------------
data "aws_iam_role" "cloudformation_deployment" {
  name = "${var.project_name}-cloudformation-deployment-role"
}

# NOTE: The deployment policy is also managed by bootstrap-iam.sh
# We don't reference it here to avoid needing iam:ListPolicies permission
