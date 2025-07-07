variable "bucket" {
  description = "The name of the S3 bucket"
  type        = string
  default     = "west-betech-tfstate"
}

variable "table" {
  description = "The name of the DynamoDB table"
  type        = string
  default     = "terraform-state-lock-table"
}

variable "region" {
  description = "The AWS region"
  type        = string
  default     = "us-west-2"
}
