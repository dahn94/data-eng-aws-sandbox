environment = "dev"
# Seu IP público em /32, para conseguir conectar no Postgres da sua máquina.
# Descubra com: curl -s https://checkip.amazonaws.com
# Vazio (o default) = nenhum acesso de fora da VPC.
allowed_cidr_blocks  = []
network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/network/dev/terraform.tfstate"
