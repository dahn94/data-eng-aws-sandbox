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

# Sem bloco de LocalStack: o emulador não executa SQL de Redshift nem integração
# zero-ETL, então um apply local validaria sintaxe e nada do comportamento que
# este workload existe para mostrar. Ver
# ../federated-query/adr/0002-onde-o-emulador-deixa-de-ensinar.md.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "DataEngSandbox"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DataTeam"
      Component   = "workload-zero-etl"
    }
  }
}
