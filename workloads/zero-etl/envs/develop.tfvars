environment = "dev"
region      = "us-east-2"

network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/network/dev/terraform.tfstate"
rds_state_bucket     = "CHANGEME-lake-configs"
rds_state_key        = "terraform/dataeng-sandbox/platform/rds/dev/terraform.tfstate"

base_capacity_rpu = 4
source_tables     = ["dataengsandbox.public.*"]
