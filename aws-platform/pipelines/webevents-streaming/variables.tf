variable "environment" {
  description = "Ambiente de implantação (dev, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-2"
}

variable "s3_bucket_raw" {
  description = "Bucket S3 com os dados brutos (criado por aws-platform/foundation)"
  type        = string
}

variable "s3_bucket_logs" {
  description = "Bucket S3 onde o Spark Structured Streaming grava o checkpoint (criado por aws-platform/foundation)"
  type        = string
}

variable "s3_bucket_scripts" {
  description = "Bucket S3 que guarda os scripts Glue e os jars (criado por aws-platform/foundation)"
  type        = string
}

variable "opensearch_password" {
  description = <<-EOT
    Senha do usuário 'admin' do OpenSearch. Não vira argumento do job Glue (que
    ficaria em texto claro no console): é gravada num secret do Secrets Manager,
    e o job recebe apenas o ARN do secret. Sem default de propósito — passe via
    -var, TF_VAR_opensearch_password ou um *.auto.tfvars não versionado.
  EOT
  type        = string
  sensitive   = true
}

variable "streaming_host" {
  description = "Hostname onde Kafka, Schema Registry e OpenSearch são alcançáveis a partir do job Glue (ex: uma instância EC2 ou um load balancer seu)."
  type        = string
}

variable "kafka_topic" {
  description = "Tópico Kafka lido pelo job. Deve casar com topic.prefix do connector Debezium: <prefix>.<schema>.<tabela>."
  type        = string
  default     = "ecommerce.public.web_events"
}

variable "opensearch_index" {
  description = "Índice do OpenSearch onde os eventos são gravados"
  type        = string
  default     = "web_events"
}

variable "aws_endpoint_url" {
  description = <<-EOT
    URL única para onde mandar todas as chamadas da AWS. Vazio (o default) =
    AWS de verdade. Preencha com http://localhost:4566 para usar o LocalStack
    (veja local-services/localstack).
  EOT
  type        = string
  default     = ""
}
