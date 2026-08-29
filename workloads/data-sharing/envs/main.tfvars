environment = "prod"
region      = "us-east-2"

network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/aws/network/prod/terraform.tfstate"

# ATENÇÃO: este valor é por workgroup, e este workload cria DOIS.
base_capacity_rpu = 4

share_name             = "vendas_share"
consumer_database_name = "vendas_do_time_de_dados"

seed_bucket = ""
seed_prefix = "datasets/vendas/"
