terraform {
  backend "s3" {
    bucket         = "west-betech-tfstate"
    key            = "infra/stage2/terraformstatefile"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-lock-table"
  }
}
