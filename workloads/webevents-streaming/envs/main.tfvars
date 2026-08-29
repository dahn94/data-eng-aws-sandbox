environment       = "prod"
region            = "us-east-2"
s3_bucket_raw     = "CHANGEME-lake-raw-prod"
s3_bucket_logs    = "CHANGEME-lake-logs-prod"
s3_bucket_scripts = "CHANGEME-lake-configs"

# Endereço do Kafka/Schema Registry/OpenSearch para o job Glue. Deixe vazio
# quando enable_streaming_host = true: o workload cria o host e resolve o
# endereço sozinho. Só preencha se o host for seu, criado fora daqui.
streaming_host = ""

# Os dois interruptores de "rodar contra a AWS de verdade". Ligados, este
# workload cria uma EC2 Graviton spot (~US$0,017/h) hospedando Kafka e
# OpenSearch, e coloca o job Glue dentro da VPC para alcançá-la pelo IP
# privado — o que também cria um Interface Endpoint do Secrets Manager,
# ~US$7/mês parado. Leia "Onde o job roda" no README antes de ligar.
enable_streaming_host = false
enable_vpc_connection = false
network_state_bucket  = "CHANGEME-lake-configs"
network_state_key     = "terraform/dataeng-sandbox/platform/aws/network/prod/terraform.tfstate"
