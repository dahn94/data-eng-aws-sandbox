environment          = "dev"
network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/network/dev/terraform.tfstate"
# Seu IP público em /32. Vazio = nada aberto na internet; o acesso é por SSM.
# Descubra o seu com: curl -s https://checkip.amazonaws.com
# NUNCA use 0.0.0.0/0 aqui — os serviços sobem sem autenticação.
allowed_cidr_blocks = []

# Graviton no spot: ~US$0,017/h. Ver a seção de custo do README.
instance_type    = "t4g.large"
root_volume_size = 30
spot             = true
