# Sem backend remoto de propósito: este é o único root module que roda com
# state local. Ele cria justamente o bucket que os outros usam como backend —
# se dependesse de um backend S3, seria um ovo-e-galinha.
terraform {
  required_version = ">= 1.9"

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
      Component   = "foundation"
    }
  }
}
