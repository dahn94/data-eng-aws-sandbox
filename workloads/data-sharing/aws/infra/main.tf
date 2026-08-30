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
  name     = "dataeng-sandbox-share-${var.environment}"
  has_seed = var.seed_bucket != ""

  producer_name = "${local.name}-producer"
  consumer_name = "${local.name}-consumer"

  base_table = "vendas"
}

# ---------------------------------------------------------------------------
# Rede das duas pontas
# ---------------------------------------------------------------------------

# Um security group para os dois workgroups: eles são as duas pontas do MESMO
# experimento e vivem e morrem juntos. Separá-los sugeriria um isolamento que a
# demonstração não tem — o isolamento aqui é de namespace e permissão, não de
# rede.
resource "aws_security_group" "redshift" {
  name        = "${local.name}-redshift"
  description = "Workgroups Redshift Serverless do workload data-sharing"
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
  description       = "Saída dos workgroups"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Permissão de leitura do S3 para semear o produtor
# ---------------------------------------------------------------------------

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
# As duas pontas
# ---------------------------------------------------------------------------

# O produtor: quem é dono do dado. Ele continua dono depois do share — é esse o
# ponto do workload.
module "producer" {
  source = "../../../../platform/aws/modules/redshift-serverless"

  name        = local.producer_name
  environment = var.environment

  database_name  = "vendas"
  admin_username = "admin"
  admin_password = var.redshift_admin_password

  subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids = [aws_security_group.redshift.id]

  base_capacity_rpu    = var.base_capacity_rpu
  publicly_accessible  = false
  enhanced_vpc_routing = false

  iam_role_arns        = local.has_seed ? [aws_iam_role.redshift_copy[0].arn] : []
  default_iam_role_arn = local.has_seed ? aws_iam_role.redshift_copy[0].arn : null
}

# O consumidor: outro time, outro namespace, outra fatura de consulta. Não
# recebe cópia nenhuma — recebe permissão.
module "consumer" {
  source = "../../../../platform/aws/modules/redshift-serverless"

  name        = local.consumer_name
  environment = var.environment

  database_name  = "marketing"
  admin_username = "admin"
  admin_password = var.redshift_admin_password

  subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids = [aws_security_group.redshift.id]

  base_capacity_rpu    = var.base_capacity_rpu
  publicly_accessible  = false
  enhanced_vpc_routing = false
}

# ---------------------------------------------------------------------------
# Credenciais para a Data API
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "producer_admin" {
  name                    = "${local.producer_name}-admin"
  description             = "Credencial do admin do namespace produtor"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "producer_admin" {
  secret_id = aws_secretsmanager_secret.producer_admin.id

  secret_string = jsonencode({
    username = module.producer.admin_username
    password = var.redshift_admin_password
    host     = module.producer.endpoint_address
    port     = module.producer.endpoint_port
    dbname   = module.producer.database_name
  })
}

resource "aws_secretsmanager_secret" "consumer_admin" {
  name                    = "${local.consumer_name}-admin"
  description             = "Credencial do admin do namespace consumidor"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "consumer_admin" {
  secret_id = aws_secretsmanager_secret.consumer_admin.id

  secret_string = jsonencode({
    username = module.consumer.admin_username
    password = var.redshift_admin_password
    host     = module.consumer.endpoint_address
    port     = module.consumer.endpoint_port
    dbname   = module.consumer.database_name
  })
}

# ---------------------------------------------------------------------------
# Lado do produtor: a tabela, a semente e o share
# ---------------------------------------------------------------------------

resource "aws_redshiftdata_statement" "create_table" {
  workgroup_name = module.producer.workgroup_name
  database       = module.producer.database_name
  secret_arn     = aws_secretsmanager_secret.producer_admin.arn

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

  depends_on = [aws_secretsmanager_secret_version.producer_admin]
}

resource "aws_redshiftdata_statement" "seed" {
  count = local.has_seed ? 1 : 0

  workgroup_name = module.producer.workgroup_name
  database       = module.producer.database_name
  secret_arn     = aws_secretsmanager_secret.producer_admin.arn

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

# O share em si. Repare no que NÃO existe aqui: nenhum job, nenhum bucket de
# export, nenhum agendamento. A fronteira entre os dois times virou uma
# permissão.
resource "aws_redshiftdata_statement" "create_datashare" {
  workgroup_name = module.producer.workgroup_name
  database       = module.producer.database_name
  secret_arn     = aws_secretsmanager_secret.producer_admin.arn

  sql = <<-SQL
    CREATE DATASHARE ${var.share_name};
    ALTER DATASHARE ${var.share_name} ADD SCHEMA public;
    ALTER DATASHARE ${var.share_name} ADD ALL TABLES IN SCHEMA public;
    GRANT USAGE ON DATASHARE ${var.share_name} TO NAMESPACE '${module.consumer.namespace_id}';
  SQL

  depends_on = [
    aws_redshiftdata_statement.create_table,
    aws_redshiftdata_statement.seed,
  ]
}

# ---------------------------------------------------------------------------
# Lado do consumidor: montar o banco compartilhado
# ---------------------------------------------------------------------------

# Um banco sem armazenamento. As linhas continuam no produtor; o consumidor
# recebe uma referência e paga só o próprio processamento de consulta.
resource "aws_redshiftdata_statement" "mount_datashare" {
  workgroup_name = module.consumer.workgroup_name
  database       = module.consumer.database_name
  secret_arn     = aws_secretsmanager_secret.consumer_admin.arn

  sql = <<-SQL
    CREATE DATABASE ${var.consumer_database_name}
      FROM DATASHARE ${var.share_name}
      OF NAMESPACE '${module.producer.namespace_id}';
  SQL

  depends_on = [
    aws_secretsmanager_secret_version.consumer_admin,
    aws_redshiftdata_statement.create_datashare,
  ]
}
