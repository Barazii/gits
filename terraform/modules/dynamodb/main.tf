resource "aws_dynamodb_table" "jobs" {
  name         = var.table_name
  billing_mode = var.billing_mode

  # Only set provisioned throughput if billing mode is PROVISIONED
  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  # Primary key
  hash_key  = "user_id"
  range_key = "added_at"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "added_at"
    type = "N"
  }

  attribute {
    name = "job_id"
    type = "S"
  }

  # Global Secondary Index on job_id
  global_secondary_index {
    name            = "job_id-index"
    hash_key        = "job_id"
    projection_type = "ALL"
    read_capacity   = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
    write_capacity  = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = var.table_name
  }
}
