variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
}

variable "encryption_type" {
  description = "Encryption type (AES256 or KMS)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (only used if encryption_type is KMS)"
  type        = string
  default     = ""
}

variable "images_to_keep" {
  description = "Number of images to keep in lifecycle policy"
  type        = number
}
