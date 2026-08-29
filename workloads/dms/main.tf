data "terraform_remote_state" "network" {
  backend = "s3"
  config = merge({
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.region
  }, local.localstack_state_config)
}

data "terraform_remote_state" "rds" {
  backend = "s3"
  config = merge({
    bucket = var.rds_state_bucket
    key    = var.rds_state_key
    region = var.region
  }, local.localstack_state_config)
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
    server_name   = data.terraform_remote_state.rds.outputs.db_instance_address
    port          = data.terraform_remote_state.rds.outputs.db_instance_port
    database_name = data.terraform_remote_state.rds.outputs.db_name
    username      = data.terraform_remote_state.rds.outputs.db_username
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
