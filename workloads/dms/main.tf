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

  name        = "dataeng-sandbox-dms-src-${var.environment}"
  environment = var.environment

  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr            = data.terraform_remote_state.network.outputs.vpc_cidr
  public_subnet_ids   = data.terraform_remote_state.network.outputs.public_subnet_ids
  allowed_cidr_blocks = var.source_db_allowed_cidr_blocks

  # Casa com o default do PGDATABASE do local-services/data-generator.
  db_name     = "dataengsandbox"
  db_username = "postgres"
  db_password = var.rds_password

  instance_class    = var.source_db_instance_class
  allocated_storage = var.source_db_allocated_storage

  # CDC por replicação lógica é literalmente o que este workload faz.
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

module "dms" {
  source = "../../modules/dms"

  environment                 = var.environment
  replication_subnet_group_id = data.terraform_remote_state.network.outputs.dms_subnet_group_id
  replication_instance_class  = var.replication_instance_class
  create_vpc_role             = var.create_vpc_role

  source_endpoint_config = {
    endpoint_id = "postgres-source-${var.environment}"
    engine_name = "postgres"
    # `address`, não `endpoint`: o segundo vem como host:porta e o DMS rejeita.
    server_name   = local.src_address
    port          = local.src_port
    database_name = local.src_db_name
    username      = local.src_username
    password      = var.rds_password
  }

  # Este prefixo é o contrato com os workloads: o DMS grava em
  # <bucket_folder>/<schema>/<tabela>/, e é daí que elas leem.
  target_s3_config = {
    bucket_name   = var.s3_bucket_raw
    bucket_folder = var.raw_output_prefix
  }

  table_mappings = jsonencode({
    rules = [
      {
        rule-type = "selection"
        rule-id   = "1"
        rule-name = "1"
        object-locator = {
          schema-name = "public"
          table-name  = "%"
        }
        rule-action = "include"
      }
    ]
  })
}
