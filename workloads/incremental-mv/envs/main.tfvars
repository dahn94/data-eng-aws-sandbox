environment = "prod"
region      = "us-east-2"

network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/network/prod/terraform.tfstate"

base_capacity_rpu = 4
mv_auto_refresh   = true

seed_bucket = ""
seed_prefix = "datasets/vendas/"
