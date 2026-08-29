environment = "prod"
region      = "us-east-2"

network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/network/prod/terraform.tfstate"
rds_state_bucket     = "CHANGEME-lake-configs"
rds_state_key        = "terraform/dataeng-sandbox/sources/rds/prod/terraform.tfstate"

base_capacity_rpu = 4
source_tables     = ["dataengsandbox.public.*"]
