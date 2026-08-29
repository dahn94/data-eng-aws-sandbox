environment       = "dev"
region            = "us-east-2"
s3_bucket_raw     = "CHANGEME-lake-raw-dev"
s3_bucket_logs    = "CHANGEME-lake-logs-dev"
s3_bucket_scripts = "CHANGEME-lake-configs"

# Host onde Kafka, Schema Registry e OpenSearch respondem para o job Glue.
# Precisa ser alcançável DE DENTRO DA AWS: o job Glue roda lá, e o seu
# localhost não serve. Normalmente o IP público de lab/streaming-host (veja o
# output public_ip dela). Troque antes de aplicar de verdade.
streaming_host = "CHANGEME.exemplo.invalid"
