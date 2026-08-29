data "terraform_remote_state" "network" {
  backend = "s3"
  config = merge({
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.region
  }, local.localstack_state_config)
}

module "rds_postgres" {
  source = "../../modules/rds"

  environment         = var.environment
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr            = data.terraform_remote_state.network.outputs.vpc_cidr
  public_subnet_ids   = data.terraform_remote_state.network.outputs.public_subnet_ids
  allowed_cidr_blocks = var.allowed_cidr_blocks

  # O nome do banco casa com o default do PGDATABASE do local-services/data-generator.
  db_name     = "dataengsandbox"
  db_username = "postgres"
  db_password = var.rds_password

  instance_class    = var.instance_class
  allocated_storage = 20
}
