environment          = "dev"
network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/network/dev/terraform.tfstate"
# Seu IP público em /32 para SSH. Vazio = nenhum acesso SSH.
# Descubra com: curl -s https://checkip.amazonaws.com
ssh_allowed_cidr_blocks = []
