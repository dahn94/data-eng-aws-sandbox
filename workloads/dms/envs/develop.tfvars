environment          = "dev"
s3_bucket_raw        = "CHANGEME-lake-raw-dev"
network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/network/dev/terraform.tfstate"

# Este workload cria a própria fonte. Para apontar para um Postgres que já
# existe, ponha create_source_db = false e preencha rds_state_bucket/key.
create_source_db = true
