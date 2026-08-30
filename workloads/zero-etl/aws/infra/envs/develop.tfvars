environment = "dev"
region      = "us-east-2"

network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/aws/network/dev/terraform.tfstate"

base_capacity_rpu = 4
source_tables     = ["dataengsandbox.public.*"]

# Este workload cria a própria fonte. Para apontar para um Postgres que já
# existe, ponha create_source_db = false e preencha rds_state_bucket/key.
create_source_db = true
