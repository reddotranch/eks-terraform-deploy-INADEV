terraform {
  required_version = ">=0.12.0"
  backend "s3" {
    key            = "infra/terraformstatefile"
    bucket         = "betech-terraform-state-bucket-2025"
    region         = "us-west-2"
    dynamodb_table = "betech-terraform-locks"
  }
}
