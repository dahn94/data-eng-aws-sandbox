data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.region
  }
}

data "terraform_remote_state" "rds" {
  backend = "s3"
  config = {
    bucket = var.rds_state_bucket
    key    = var.rds_state_key
    region = var.region
  }
}

locals {
  name = "dataeng-sandbox-federated-${var.environment}"

  # O conector roda dentro da VPC porque o Postgres não é público. Subnet
  # privada: ele não precisa de entrada da internet, só de alcançar o RDS.
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  db_address = data.terraform_remote_state.rds.outputs.db_instance_address
  db_port    = data.terraform_remote_state.rds.outputs.db_instance_port
  db_name    = data.terraform_remote_state.rds.outputs.db_name
  db_user    = data.terraform_remote_state.rds.outputs.db_username
}

# ---------------------------------------------------------------------------
# Spill e resultados
# ---------------------------------------------------------------------------

# Quando a resposta não cabe no limite de payload da Lambda, o conector grava o
# excedente aqui e o Athena lê do S3. É intermediário: expira sozinho.
resource "aws_s3_bucket" "spill" {
  bucket        = var.spill_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "spill" {
  bucket                  = aws_s3_bucket.spill.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "spill" {
  bucket = aws_s3_bucket.spill.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "spill" {
  bucket = aws_s3_bucket.spill.id
  rule {
    id     = "expira-spill"
    status = "Enabled"
    filter {}
    expiration {
      days = var.spill_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket" "results" {
  bucket        = var.athena_results_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Credencial
# ---------------------------------------------------------------------------

# O conector espera um secret com {"username": ..., "password": ...} e o
# encontra pelo prefixo do nome. A senha nunca vira argumento da Lambda.
resource "aws_secretsmanager_secret" "postgres" {
  name                    = "${local.name}-postgres"
  description             = "Credencial que o conector federado do Athena usa para ler o Postgres"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id
  secret_string = jsonencode({
    username = local.db_user
    password = var.rds_password
  })
}

# ---------------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------------

resource "aws_security_group" "connector" {
  name        = "${local.name}-connector"
  description = "Lambda do conector federado do Athena"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "${local.name}-connector"
  }
}

# Saída livre: a Lambda precisa falar com o Postgres, o S3, o Secrets Manager e
# os endpoints do Athena. Restringir por CIDR aqui daria falsa sensação de
# controle — o que de fato limita é a regra de entrada do RDS, abaixo.
resource "aws_vpc_security_group_egress_rule" "connector_all" {
  security_group_id = aws_security_group.connector.id
  description       = "Saída para RDS, S3, Secrets Manager e Athena"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Quem chega depois declara o próprio acesso: o RDS não precisa conhecer seus
# consumidores. Por isso sources/rds passou a exportar security_group_id.
resource "aws_vpc_security_group_ingress_rule" "rds_from_connector" {
  security_group_id            = data.terraform_remote_state.rds.outputs.security_group_id
  description                  = "Postgres a partir do conector federado do Athena"
  referenced_security_group_id = aws_security_group.connector.id
  from_port                    = local.db_port
  to_port                      = local.db_port
  ip_protocol                  = "tcp"
}

# ---------------------------------------------------------------------------
# O conector
# ---------------------------------------------------------------------------

# A AWS publica o conector como aplicação no Serverless Application Repository.
# Instalar de lá (em vez de empacotar a Lambda aqui) é o caminho suportado e o
# que se faz em produção — a alternativa é manter build de um jar de terceiro.
resource "aws_serverlessapplicationrepository_cloudformation_stack" "postgres_connector" {
  name           = "${local.name}-connector"
  application_id = "arn:aws:serverlessrepo:us-east-1:292517598671:applications/AthenaPostgreSQLConnector"

  capabilities = [
    "CAPABILITY_IAM",
    "CAPABILITY_RESOURCE_POLICY",
  ]

  parameters = {
    LambdaFunctionName = "${local.name}-connector"
    SecretNamePrefix   = aws_secretsmanager_secret.postgres.name
    SpillBucket        = aws_s3_bucket.spill.id
    SpillPrefix        = "spill"
    SecurityGroupIds   = aws_security_group.connector.id
    SubnetIds          = join(",", local.subnet_ids)
    LambdaMemory       = var.connector_lambda_memory_mb
    LambdaTimeout      = var.connector_lambda_timeout_s

    # A string de conexão referencia o secret por nome; a senha resolve em
    # runtime, dentro da Lambda. `${...}` escapado para o Terraform não
    # interpolar o que é sintaxe do próprio conector.
    DefaultConnectionString = "postgres://jdbc:postgresql://${local.db_address}:${local.db_port}/${local.db_name}?$${${aws_secretsmanager_secret.postgres.name}}"
  }

  depends_on = [aws_secretsmanager_secret_version.postgres]
}

# ---------------------------------------------------------------------------
# Athena
# ---------------------------------------------------------------------------

# O catálogo é o que faz o Postgres aparecer como uma fonte dentro do Athena.
# Daqui em diante é SQL: nenhum dado foi copiado para lugar nenhum.
resource "aws_athena_data_catalog" "postgres" {
  name        = replace("${local.name}-postgres", "-", "_")
  description = "Postgres transacional (sources/rds) consultado sem cópia"
  type        = "LAMBDA"

  parameters = {
    function = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${local.name}-connector"
  }

  depends_on = [aws_serverlessapplicationrepository_cloudformation_stack.postgres_connector]
}

# Workgroup próprio para o custo deste caminho aparecer separado na fatura —
# é metade do ponto do experimento. Sem isso, a query federada se mistura ao
# resto do Athena e o ADR não tem número para citar.
resource "aws_athena_workgroup" "federated" {
  name        = local.name
  description = "Queries federadas — isola o custo deste caminho para comparação"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.results.id}/results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  force_destroy = true
}
