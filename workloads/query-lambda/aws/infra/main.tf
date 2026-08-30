data "aws_caller_identity" "current" {}

locals {
  function_name = "dataeng-sandbox-s3tables-duckdb-${var.environment}"
  lakehouse_arn = var.lakehouse_arn != "" ? var.lakehouse_arn : "arn:aws:s3tables:${var.region}:${data.aws_caller_identity.current.account_id}:bucket/dataeng-sandbox-lakehouse-${var.environment}"

  # Só cria a Lambda quando já existe imagem publicada. Veja o README: o
  # primeiro apply cria só o repositório ECR, você publica a imagem, e o
  # segundo apply (com image_tag preenchido) cria a função.
  create_function = var.image_tag != ""
}

# O repositório ECR passa a ser gerenciado pelo Terraform. Antes ele era criado
# por dentro do build_and_push.sh, fora do state — e nada no repositório dizia
# que ele precisava existir.
resource "aws_ecr_repository" "duckdb" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Sem isso, cada build acumula uma imagem de ~300 MB no ECR para sempre.
resource "aws_ecr_lifecycle_policy" "duckdb" {
  repository = aws_ecr_repository.duckdb.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantém apenas as 5 imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

module "lambda_function_duckdb" {
  source = "../../../../platform/aws/modules/lambda_ecr"
  count  = local.create_function ? 1 : 0

  function_name = local.function_name
  description   = "Consulta as tabelas Iceberg do S3 Tables com DuckDB"

  # Tag imutável e explícita: com :latest o Terraform nunca percebe que a
  # imagem mudou e a função continua rodando o código antigo.
  image_uri = "${aws_ecr_repository.duckdb.repository_url}:${var.image_tag}"

  timeout                = 900
  memory_size            = 2048
  ephemeral_storage_size = 2048

  create_function_url    = var.create_function_url
  function_url_auth_type = "AWS_IAM"
  allowed_origins        = var.allowed_origins

  s3tables_bucket_arn = local.lakehouse_arn
  readable_buckets    = var.readable_buckets

  environment_variables = {
    ENVIRONMENT     = var.environment
    DEFAULT_CATALOG = local.lakehouse_arn
  }
}
