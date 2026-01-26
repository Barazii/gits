#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

#------------------------------------------------------------------------------
# VPC Flow Logs
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.project_name}-flow-logs"
  retention_in_days = var.flow_logs_retention_days

  tags = {
    Name = "${var.project_name}-flow-logs"
  }
}

resource "aws_flow_log" "main" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_group_name           = aws_cloudwatch_log_group.flow_logs.name
  iam_role_arn             = var.vpc_flow_logs_role_arn
  max_aggregation_interval = 60

  tags = {
    Name = "${var.project_name}-vpc-flow-log"
  }
}

#------------------------------------------------------------------------------
# Internet Gateway
#------------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

#------------------------------------------------------------------------------
# Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

#------------------------------------------------------------------------------
# NAT Gateway
#------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

#------------------------------------------------------------------------------
# Route Tables
#------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

#------------------------------------------------------------------------------
# VPC Endpoints - Gateway
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-dynamodb-endpoint"
  }
}

#------------------------------------------------------------------------------
# VPC Endpoints - Interface
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-secretsmanager-endpoint"
  }
}

resource "aws_vpc_endpoint" "events" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.events"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-events-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ecr-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ecr-dkr-endpoint"
  }
}

resource "aws_vpc_endpoint" "codebuild" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.codebuild"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-codebuild-endpoint"
  }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-logs-endpoint"
  }
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-sts-endpoint"
  }
}

#------------------------------------------------------------------------------
# GitHub Prefix Lists
#------------------------------------------------------------------------------
resource "aws_ec2_managed_prefix_list" "github_https" {
  name           = "${var.project_name}-github-https"
  address_family = "IPv4"
  max_entries    = 20

  dynamic "entry" {
    for_each = var.github_core_ranges
    content {
      cidr        = entry.value
      description = "GitHub core range"
    }
  }

  dynamic "entry" {
    for_each = var.github_web_api_ranges
    content {
      cidr        = entry.value
      description = "GitHub web/api endpoint"
    }
  }

  tags = {
    Name    = "${var.project_name}-github-https-prefix-list"
    Purpose = "GitHub HTTPS traffic (API and web cloning)"
  }
}

resource "aws_ec2_managed_prefix_list" "github_ssh" {
  name           = "${var.project_name}-github-ssh"
  address_family = "IPv4"
  max_entries    = 20

  dynamic "entry" {
    for_each = var.github_core_ranges
    content {
      cidr        = entry.value
      description = "GitHub core range"
    }
  }

  dynamic "entry" {
    for_each = var.github_ssh_ranges
    content {
      cidr        = entry.value
      description = "GitHub git SSH endpoint"
    }
  }

  tags = {
    Name    = "${var.project_name}-github-ssh-prefix-list"
    Purpose = "GitHub SSH traffic (Git SSH cloning)"
  }
}

#------------------------------------------------------------------------------
# Security Groups
#------------------------------------------------------------------------------

# VPC Endpoint Security Group
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.project_name}-vpc-endpoint-sg"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTPS from within VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-vpc-endpoint-sg"
  }
}

# CodeBuild Security Group
resource "aws_security_group" "codebuild" {
  name        = "${var.project_name}-codebuild-sg"
  description = "Security group for CodeBuild"
  vpc_id      = aws_vpc.main.id

  egress {
    description     = "Allow SSH to GitHub for Git cloning"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    prefix_list_ids = [aws_ec2_managed_prefix_list.github_ssh.id]
  }

  egress {
    description     = "Allow HTTPS to GitHub for API and web cloning"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_ec2_managed_prefix_list.github_https.id]
  }

  egress {
    description = "Allow HTTPS to VPC endpoints within VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "Allow HTTPS to S3 via gateway endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [var.s3_prefix_list_id]
  }

  tags = {
    Name = "${var.project_name}-codebuild-sg"
  }
}

# Schedule Lambda Security Group
resource "aws_security_group" "schedule_lambda" {
  name        = "${var.project_name}-schedule-lambda-sg"
  description = "Security group for schedule Lambda"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "Allow HTTPS to S3 via gateway endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [var.s3_prefix_list_id]
  }

  egress {
    description     = "Allow HTTPS to DynamoDB via gateway endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [var.dynamodb_prefix_list_id]
  }

  tags = {
    Name = "${var.project_name}-schedule-lambda-sg"
  }
}

# Delete Lambda Security Group
resource "aws_security_group" "delete_lambda" {
  name        = "${var.project_name}-delete-lambda-sg"
  description = "Security group for Delete Lambda"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "Allow HTTPS to DynamoDB via gateway endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [var.dynamodb_prefix_list_id]
  }

  tags = {
    Name = "${var.project_name}-delete-lambda-sg"
  }
}

# Status Lambda Security Group
resource "aws_security_group" "status_lambda" {
  name        = "${var.project_name}-status-lambda-sg"
  description = "Security group for status Lambda"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "Allow HTTPS to DynamoDB via gateway endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [var.dynamodb_prefix_list_id]
  }

  tags = {
    Name = "${var.project_name}-status-lambda-sg"
  }
}

# CodeBuildLens Lambda Security Group
resource "aws_security_group" "codebuildlens_lambda" {
  name        = "${var.project_name}-codebuildlens-lambda-sg"
  description = "Security group for CodeBuildLens Lambda"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "Allow HTTPS to DynamoDB via gateway endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [var.dynamodb_prefix_list_id]
  }

  tags = {
    Name = "${var.project_name}-codebuildlens-lambda-sg"
  }
}
