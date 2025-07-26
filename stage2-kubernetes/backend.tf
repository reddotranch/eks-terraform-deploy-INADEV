terraform {
  backend "s3" {
    bucket         = "betech-terraform-state-bucket-2025"
    key            = "infra/stage2/terraformstatefile"
    region         = "us-west-2"
    dynamodb_table = "betech-terraform-locks"
  }
}
