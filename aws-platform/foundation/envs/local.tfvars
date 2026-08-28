# Ambiente LocalStack. Diferente de develop/main, o prefixo de bucket é fixo:
# no emulador não existe namespace global, então não há risco de colisão.
environment      = "local"
region           = "us-east-1"
bucket_prefix    = "sandbox"
aws_endpoint_url = "http://localhost:4566"
