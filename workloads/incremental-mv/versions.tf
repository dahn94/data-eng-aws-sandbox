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

# Sem bloco de LocalStack: o emulador não tem motor SQL de Redshift, e uma
# materialized view com AUTO REFRESH é exatamente comportamento de motor — não
# há o que validar contra um emulador aqui. Ver
# ../federated-query/adr/0002-onde-o-emulador-deixa-de-ensinar.md.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "DataEngSandbox"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DataTeam"
      Component   = "workload-incremental-mv"
    }
  }
}
