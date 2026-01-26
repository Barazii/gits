variable "bucket_name" {
  description = "S3 bucket name"
  type        = string
}

variable "enable_versioning" {
  description = "Enable versioning"
  type        = bool
}

variable "block_public_access" {
  description = "Block public access"
  type        = bool
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
}
