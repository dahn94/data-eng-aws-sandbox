environment          = "local"
region               = "us-east-1"
allowed_cidr_blocks  = ["0.0.0.0/0"] # emulador local, não é a internet
network_state_bucket = "sandbox-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/network/local/terraform.tfstate"
aws_endpoint_url     = "http://localhost:4566"
