variable "table_name" {
  description = "DynamoDB table name"
  type        = string
}

variable "billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
}

variable "point_in_time_recovery" {
  description = "Enable point-in-time recovery"
  type        = bool
}

variable "read_capacity" {
  description = "Read capacity units"
  type        = number
}

variable "write_capacity" {
  description = "Write capacity units"
  type        = number
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
}
