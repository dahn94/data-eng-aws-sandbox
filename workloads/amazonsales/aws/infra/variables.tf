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
  description = "Bucket S3 com os dados brutos, entrada da pipeline (criado por platform/aws/foundation)"
  type        = string
}

variable "s3_bucket_curated" {
  description = "Bucket S3 onde os resultados de Data Quality são publicados (criado por platform/aws/foundation)"
  type        = string
}

variable "s3_bucket_scripts" {
  description = "Bucket S3 que guarda os scripts Glue e os jars (criado por platform/aws/foundation)"
  type        = string
}

variable "raw_input_prefix" {
  description = <<-EOT
    Prefixo dentro de s3_bucket_raw onde a pipeline procura os dados de vendas.
    O default casa com o caminho que o DMS escreve: <bucket_folder>/<schema>/<tabela>.
  EOT
  type        = string
  default     = "raw/postgres/public/amazon/"
}

variable "iceberg_catalog_jar_name" {
  description = <<-EOT
    Nome do arquivo do jar do catálogo S3 Tables para Iceberg, dentro de
    scripts/jars/. O Terraform envia esse arquivo para o bucket de scripts e
    aponta o --extra-jars dos jobs para lá.
  EOT
  type        = string
  default     = "s3-tables-catalog-for-iceberg-runtime-0.1.7.jar"
}

variable "lakehouse_arn" {
  description = "ARN do bucket S3 Tables. Vazio = montado a partir da conta, região e ambiente, casando com o nome criado por platform/aws/foundation."
  type        = string
  default     = ""
}
