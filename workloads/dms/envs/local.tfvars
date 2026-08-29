environment          = "local"
region               = "us-east-1"
s3_bucket_raw        = "sandbox-lake-raw-local"
network_state_bucket = "sandbox-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/network/local/terraform.tfstate"
aws_endpoint_url     = "http://localhost:4566"

# Explícito porque o default mudou de significado: este workload cria o próprio
# Postgres de origem, inclusive no LocalStack. Para apontar para um banco que já
# existe, ponha false e preencha rds_state_bucket/key.
create_source_db = true
