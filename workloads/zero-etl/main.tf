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

# ---------------------------------------------------------------------------
# A fonte: o Postgres transacional que este workload lê
# ---------------------------------------------------------------------------

module "source_db" {
  count  = var.create_source_db ? 1 : 0
  source = "../../modules/rds"

  name        = "dataeng-sandbox-zero-etl-src-${var.environment}"
  environment = var.environment

  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr            = data.terraform_remote_state.network.outputs.vpc_cidr
  public_subnet_ids   = data.terraform_remote_state.network.outputs.public_subnet_ids
  allowed_cidr_blocks = var.source_db_allowed_cidr_blocks

  # Casa com o default do PGDATABASE do tools/data-generator.
  db_name     = "dataengsandbox"
  db_username = "postgres"
  db_password = var.rds_password

  instance_class    = var.source_db_instance_class
  allocated_storage = var.source_db_allocated_storage

  # A integração gerenciada usa replicação lógica por baixo.
  enable_logical_replication = true
}

# Só existe quando a fonte NÃO é deste workload — o cenário realista, em que o
# banco pertence a outro time e você só lê.
data "terraform_remote_state" "rds" {
  count   = var.create_source_db ? 0 : 1
  backend = "s3"
  config = {
    bucket = var.rds_state_bucket
    key    = var.rds_state_key
    region = var.region
  }
}

locals {
  src_address  = var.create_source_db ? module.source_db[0].db_instance_address : data.terraform_remote_state.rds[0].outputs.db_instance_address
  src_port     = var.create_source_db ? module.source_db[0].db_instance_port : data.terraform_remote_state.rds[0].outputs.db_instance_port
  src_db_name  = var.create_source_db ? module.source_db[0].db_name : data.terraform_remote_state.rds[0].outputs.db_name
  src_username = var.create_source_db ? module.source_db[0].db_username : data.terraform_remote_state.rds[0].outputs.db_username
  src_sg_id    = var.create_source_db ? module.source_db[0].security_group_id : data.terraform_remote_state.rds[0].outputs.security_group_id
  src_arn      = var.create_source_db ? module.source_db[0].db_instance_arn : data.terraform_remote_state.rds[0].outputs.db_instance_arn
}

locals {
  name       = "dataeng-sandbox-zeroetl-${var.environment}"
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  source_arn = local.src_arn
}

# ---------------------------------------------------------------------------
# Rede do warehouse
# ---------------------------------------------------------------------------

# Este workload é dono do próprio Redshift, então é dono do security group dele.
resource "aws_security_group" "redshift" {
  name        = "${local.name}-redshift"
  description = "Workgroup Redshift Serverless do workload zero-etl"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "${local.name}-redshift"
  }
}

# Entrada só de dentro da VPC: o workgroup não é público, e quem consulta entra
# pela rede (Query Editor v2 usa a API, não esta porta).
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
# O warehouse deste workload
# ---------------------------------------------------------------------------

module "warehouse" {
  source = "../../modules/redshift-serverless"

  name        = local.name
  environment = var.environment

  database_name  = "zeroetl"
  admin_username = "admin"
  admin_password = var.redshift_admin_password

  subnet_ids         = local.subnet_ids
  security_group_ids = [aws_security_group.redshift.id]

  base_capacity_rpu   = var.base_capacity_rpu
  publicly_accessible = false

  # Enhanced VPC Routing exigiria 3 subnets em 3 AZs; o platform/aws/network cria 2.
  enhanced_vpc_routing = false

  # Exigido pela integração zero-ETL: ela replica os nomes de objeto da origem
  # como eles são, e o Postgres é sensível a maiúsculas.
  case_sensitive_identifier = true
}

# ---------------------------------------------------------------------------
# A integração
# ---------------------------------------------------------------------------

# O destino precisa autorizar a origem antes de a integração existir. Sem esta
# policy o `aws_rds_integration` falha com erro de permissão que não menciona
# que o problema está do lado do Redshift.
resource "aws_redshift_resource_policy" "inbound_integration" {
  resource_arn = module.warehouse.namespace_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "redshift.amazonaws.com" }
        Action    = "redshift:AuthorizeInboundIntegration"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.source_arn
          }
        }
      },
      {
        Effect    = "Allow"
        Principal = { AWS = data.aws_caller_identity.current.account_id }
        Action    = "redshift:CreateInboundIntegration"
      },
    ]
  })
}

# Aqui está o ponto do workload: nenhum job, nenhum agendamento, nenhum script.
# A replicação contínua do Postgres para o warehouse é uma declaração.
resource "aws_rds_integration" "postgres_to_redshift" {
  integration_name = local.name
  source_arn       = local.source_arn
  target_arn       = module.warehouse.namespace_arn

  # Sem filtro, replica o banco inteiro. Filtrar é decisão de custo e de escopo.
  # A sintaxe é uma string: itens separados por vírgula, com `include:` por padrão.
  data_filter = length(var.source_tables) > 0 ? join(",", [for t in var.source_tables : "include: ${t}"]) : null

  depends_on = [aws_redshift_resource_policy.inbound_integration]
}
