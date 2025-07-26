variable "bucket" {
  description = "The name of the S3 bucket"
  type        = string
  default     = "betech-terraform-state-bucket-2025"
}

variable "table" {
  description = "The name of the DynamoDB table"
  type        = string
  default     = "betech-terraform-locks"
}

variable "region" {
  description = "The AWS region"
  type        = string
  default     = "us-west-2"
}
