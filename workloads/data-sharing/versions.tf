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

# Sem bloco de LocalStack: datashare é um mecanismo do motor do Redshift, e o
# emulador não tem motor de Redshift. Ver
# ../federated-query/adr/0002-onde-o-emulador-deixa-de-ensinar.md.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "DataEngSandbox"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DataTeam"
      Component   = "workload-data-sharing"
    }
  }
}
