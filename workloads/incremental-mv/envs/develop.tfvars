environment = "dev"
region      = "us-east-2"

network_state_bucket = "CHANGEME-lake-configs"
network_state_key    = "terraform/dataeng-sandbox/platform/network/dev/terraform.tfstate"

base_capacity_rpu = 4
mv_auto_refresh   = true

# Vazio = sobe com a tabela base vazia. Preencha para semear a partir do lake e
# tornar os números comparáveis com os dos outros workloads (ver ../DATASET.md).
seed_bucket = ""
seed_prefix = "datasets/vendas/"
