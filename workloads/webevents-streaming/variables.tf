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
  description = "Bucket S3 com os dados brutos (criado por platform/foundation)"
  type        = string
}

variable "s3_bucket_logs" {
  description = "Bucket S3 onde o Spark Structured Streaming grava o checkpoint (criado por platform/foundation)"
  type        = string
}

variable "s3_bucket_scripts" {
  description = "Bucket S3 que guarda os scripts Glue e os jars (criado por platform/foundation)"
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

variable "enable_vpc_connection" {
  description = <<-EOT
    Faz o job Glue rodar DENTRO da VPC, por uma `aws_glue_connection` do tipo
    NETWORK. É o que permite alcançar o Kafka de `lab/streaming-host` pelo IP
    privado — sem isso, o job sai por IPs imprevisíveis da AWS e a única forma
    de deixá-lo entrar seria expor o Kafka (que roda em PLAINTEXT, sem
    autenticação) na internet aberta.

    **Custa dinheiro, e por isso nasce desligado.** Dentro da VPC o job perde o
    acesso à internet: ele alcança S3 pelo Gateway Endpoint (gratuito), mas
    precisa de um Interface Endpoint para o Secrets Manager, de onde lê a senha
    do OpenSearch. Um endpoint numa AZ custa cerca de US$0,01/h, ~US$7/mês
    parado, mais o tráfego processado.

    Ligado, este workload passa a depender de `platform/network`.
  EOT
  type        = bool
  default     = false
}

variable "network_state_bucket" {
  description = "S3 bucket com o state de platform/network. Só é lido quando enable_vpc_connection = true."
  type        = string
  default     = ""
}

variable "network_state_key" {
  description = "S3 key do state de platform/network para este ambiente. Só é lido quando enable_vpc_connection = true."
  type        = string
  default     = ""
}
