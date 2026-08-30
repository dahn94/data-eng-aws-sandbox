environment = "dev"
region      = "us-east-2"

network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/aws/network/dev/terraform.tfstate"

spill_bucket_name          = "CHANGEME-lake-federated-spill-dev"
athena_results_bucket_name = "CHANGEME-lake-federated-results-dev"

# Este workload cria a própria fonte. Para apontar para um Postgres que já
# existe, ponha create_source_db = false e preencha rds_state_bucket/key.
create_source_db = true
