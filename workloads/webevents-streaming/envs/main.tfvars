environment       = "prod"
region            = "us-east-2"
s3_bucket_raw     = "CHANGEME-lake-raw-prod"
s3_bucket_logs    = "CHANGEME-lake-logs-prod"
s3_bucket_scripts = "CHANGEME-lake-configs"

# Host onde Kafka, Schema Registry e OpenSearch respondem para o job Glue.
# Normalmente o IP público da instância de lab/ec2 (veja o output
# public_ip dela). Troque antes de aplicar de verdade.
streaming_host = "CHANGEME.exemplo.invalid"
