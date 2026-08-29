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

# Sem bloco de LocalStack, ao contrário dos workloads mais antigos: o conector
# federado do Athena é uma aplicação do Serverless Application Repository que o
# emulador não resolve. Ver adr/0002-onde-o-emulador-deixa-de-ensinar.md.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "DataEngSandbox"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DataTeam"
      Component   = "workload-federated-query"
    }
  }
}
