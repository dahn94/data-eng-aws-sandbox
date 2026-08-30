data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.region
  }
}

locals {
  name     = "dataeng-sandbox-incmv-${var.environment}"
  has_seed = var.seed_bucket != ""

  # A tabela base e a view derivada. Ficam em local para que o README, o
  # nfr.md e o ADR possam citar exatamente o SQL que roda.
  base_table = "vendas"
  mv_name    = "receita_por_hora"
}

# ---------------------------------------------------------------------------
# Rede do warehouse
# ---------------------------------------------------------------------------

# Este workload é dono do próprio Redshift, então é dono do security group dele.
# Sim, o zero-etl cria outro igual: infraestrutura duplicada é o preço de cada
# pasta subir sozinha. O que não se duplica é código — ambos instanciam
# ../../modules/redshift-serverless.
resource "aws_security_group" "redshift" {
  name        = "${local.name}-redshift"
  description = "Workgroup Redshift Serverless do workload incremental-mv"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "${local.name}-redshift"
  }
}

resource "aws_vpc_security_group_ingress_rule" "redshift_from_vpc" {
  security_group_id = aws_security_group.redshift.id
  description       = "Redshift a partir da própria VPC"
  cidr_ipv4         = data.terraform_remote_state.network.outputs.vpc_cidr
  from_port         = 5439
  to_port           = 5439
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "redshift_all" {
  security_group_id = aws_security_group.redshift.id
  description       = "Saída do workgroup"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Permissão de leitura do S3, só se houver semente
# ---------------------------------------------------------------------------

# O COPY roda como o Redshift, não como você: quem lê o S3 é uma role assumida
# pelo namespace. Sem semente configurada, esta role nem existe — o workload
# sobe com a tabela vazia e nada de IAM sobra pendurado.
resource "aws_iam_role" "redshift_copy" {
  count = local.has_seed ? 1 : 0

  name = "${local.name}-copy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "redshift.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "redshift_copy_s3" {
  count = local.has_seed ? 1 : 0

  name = "read-seed"
  role = aws_iam_role.redshift_copy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.seed_bucket}/${var.seed_prefix}*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.seed_bucket}"
        Condition = {
          StringLike = { "s3:prefix" = ["${var.seed_prefix}*"] }
        }
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# O warehouse deste workload
# ---------------------------------------------------------------------------

module "warehouse" {
  source = "../../../../platform/aws/modules/redshift-serverless"

  name        = local.name
  environment = var.environment

  database_name  = "analytics"
  admin_username = "admin"
  admin_password = var.redshift_admin_password

  subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids = [aws_security_group.redshift.id]

  base_capacity_rpu   = var.base_capacity_rpu
  publicly_accessible = false

  # Enhanced VPC Routing exigiria 3 subnets em 3 AZs; o platform/aws/network cria 2.
  enhanced_vpc_routing = false

  iam_role_arns        = local.has_seed ? [aws_iam_role.redshift_copy[0].arn] : []
  default_iam_role_arn = local.has_seed ? aws_iam_role.redshift_copy[0].arn : null
}

# ---------------------------------------------------------------------------
# Credencial para a Data API
# ---------------------------------------------------------------------------

# O SQL abaixo roda pela Redshift Data API, que é um endpoint da AWS — não
# precisa de rota até a subnet privada. Ela se autentica com um segredo, e não
# com a identidade IAM de quem roda o Terraform: uma identidade IAM nova entra
# no banco sem permissão de criar nada, e o CREATE TABLE falharia.
resource "aws_secretsmanager_secret" "redshift_admin" {
  name        = "${local.name}-admin"
  description = "Credencial do admin do Redshift do workload incremental-mv"

  # Sandbox: sem janela de recuperação, o destroy libera o nome na hora. Em
  # produção isto seria o default de 30 dias.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "redshift_admin" {
  secret_id = aws_secretsmanager_secret.redshift_admin.id

  secret_string = jsonencode({
    username = module.warehouse.admin_username
    password = var.redshift_admin_password
    host     = module.warehouse.endpoint_address
    port     = module.warehouse.endpoint_port
    dbname   = module.warehouse.database_name
  })
}

# ---------------------------------------------------------------------------
# A tabela base, a semente e a view
# ---------------------------------------------------------------------------

# Estes três recursos executam SQL uma vez, na criação. O Terraform não
# reconcilia o estado do banco depois disso: mudar o SQL recria o statement,
# não altera o objeto existente. É a fronteira honesta do IaC aqui, e está
# registrada no ADR.
resource "aws_redshiftdata_statement" "create_table" {
  workgroup_name = module.warehouse.workgroup_name
  database       = module.warehouse.database_name
  secret_arn     = aws_secretsmanager_secret.redshift_admin.arn

  sql = <<-SQL
    CREATE TABLE IF NOT EXISTS ${local.base_table} (
      order_id    BIGINT,
      customer_id BIGINT,
      pedido_em   TIMESTAMP,
      valor       DECIMAL(12,2),
      status      VARCHAR(32)
    )
    DISTSTYLE KEY DISTKEY (customer_id)
    SORTKEY (pedido_em);
  SQL

  depends_on = [aws_secretsmanager_secret_version.redshift_admin]
}

resource "aws_redshiftdata_statement" "seed" {
  count = local.has_seed ? 1 : 0

  workgroup_name = module.warehouse.workgroup_name
  database       = module.warehouse.database_name
  secret_arn     = aws_secretsmanager_secret.redshift_admin.arn

  sql = <<-SQL
    COPY ${local.base_table}
    FROM 's3://${var.seed_bucket}/${var.seed_prefix}'
    IAM_ROLE '${local.has_seed ? aws_iam_role.redshift_copy[0].arn : ""}'
    FORMAT AS PARQUET;
  SQL

  depends_on = [
    aws_redshiftdata_statement.create_table,
    aws_iam_role_policy.redshift_copy_s3,
  ]
}

# O workload inteiro existe por causa destas duas palavras: AUTO REFRESH.
# Você declara o resultado que deve valer sempre; o motor decide quando
# recomputar, e recomputa só o que mudou desde a última vez.
resource "aws_redshiftdata_statement" "materialized_view" {
  workgroup_name = module.warehouse.workgroup_name
  database       = module.warehouse.database_name
  secret_arn     = aws_secretsmanager_secret.redshift_admin.arn

  sql = <<-SQL
    CREATE MATERIALIZED VIEW ${local.mv_name}
      AUTO REFRESH ${var.mv_auto_refresh ? "YES" : "NO"}
    AS
    SELECT
        DATE_TRUNC('hour', pedido_em) AS hora,
        COUNT(*)                      AS pedidos,
        SUM(valor)                    AS receita
    FROM ${local.base_table}
    GROUP BY 1;
  SQL

  depends_on = [
    aws_redshiftdata_statement.create_table,
    aws_redshiftdata_statement.seed,
  ]
}
