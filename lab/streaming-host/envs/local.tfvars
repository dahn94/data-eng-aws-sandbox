environment          = "local"
region               = "us-east-1"
network_state_bucket = "sandbox-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/network/local/terraform.tfstate"
aws_endpoint_url     = "http://localhost:4566"
allowed_cidr_blocks  = []

# Spot desligado no LocalStack: o emulador não tem mercado spot, e ligar aqui
# só adicionaria um campo que ele ignora. Instância local não custa nada mesmo.
instance_type    = "t4g.large"
root_volume_size = 30
spot             = false
