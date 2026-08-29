terraform {
  required_version = ">= 1.10"

  backend "s3" {
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "DataEngSandbox"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DataTeam"
      Component   = "pipeline-webevents-streaming"
    }
  }
}
