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

# LocalStack: quando aws_endpoint_url está preenchido, todas as chamadas vão
# para o emulador local em vez da AWS de verdade.
locals {
  use_localstack = var.aws_endpoint_url != ""
}

provider "aws" {
  region = var.region

  # Com LocalStack as credenciais são fictícias e as checagens que dependem de
  # uma conta AWS real precisam ser desligadas. Contra a AWS de verdade,
  # aws_endpoint_url fica vazio e nada disto tem efeito.
  access_key                  = local.use_localstack ? "test" : null
  secret_key                  = local.use_localstack ? "test" : null
  skip_credentials_validation = local.use_localstack
  skip_metadata_api_check     = local.use_localstack
  skip_requesting_account_id  = local.use_localstack
  s3_use_path_style           = local.use_localstack

  dynamic "endpoints" {
    for_each = local.use_localstack ? [1] : []
    content {
      s3             = var.aws_endpoint_url
      s3tables       = var.aws_endpoint_url
      iam            = var.aws_endpoint_url
      sts            = var.aws_endpoint_url
      ec2            = var.aws_endpoint_url
      rds            = var.aws_endpoint_url
      dms            = var.aws_endpoint_url
      glue           = var.aws_endpoint_url
      sfn            = var.aws_endpoint_url
      lambda         = var.aws_endpoint_url
      ecr            = var.aws_endpoint_url
      logs           = var.aws_endpoint_url
      secretsmanager = var.aws_endpoint_url
      ssm            = var.aws_endpoint_url
    }
  }
  default_tags {
    tags = {
      Project     = "DataEngSandbox"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DataTeam"
      Component   = "network"
    }
  }
}
