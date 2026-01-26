# Backend configuration for remote state storage
# Uncomment and configure when ready to use remote state

# terraform {
#   backend "s3" {
#     bucket         = "gits-terraform-state"
#     key            = "terraform.tfstate"
#     region         = "eu-west-3"
#     encrypt        = true
#     dynamodb_table = "gits-terraform-locks"
#   }
# }

# For local development, state is stored locally
# Run 'terraform init' to initialize
