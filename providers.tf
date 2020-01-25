
# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
}

# Backend TF satate to Amazon S3 and lock state in DynamodB
terraform {
  backend "s3" {
    bucket = "kubernetes-terraform-state-us-east-1"
    key    = "k8s/terraformstate"
    region = "us-east-1"
    dynamodb_table = "k8slock"
    encrypt        = true
  }
}