locals {
  # O bucket de configs é compartilhado entre ambientes: guarda os states
  # (separados por key), os scripts Glue e os jars. Os buckets de dados são
  # separados por ambiente para que dev nunca escreva por cima de prod.
  configs_bucket = "${var.bucket_prefix}-lake-configs"

  data_buckets = {
    raw     = "${var.bucket_prefix}-lake-raw-${var.environment}"
    curated = "${var.bucket_prefix}-lake-curated-${var.environment}"
    logs    = "${var.bucket_prefix}-lake-logs-${var.environment}"
  }
}

# ---------------------------------------------------------------------------
# Bucket de configuração: tfstate + scripts Glue + jars
# ---------------------------------------------------------------------------
module "configs" {
  source = "../modules/s3-bucket"

  name          = local.configs_bucket
  force_destroy = var.force_destroy

  # Versionado: é o que permite recuperar um tfstate sobrescrito.
  versioning = true

  # Sem expiração: script, jar e state não envelhecem.
  expiration_days = 0
}

# ---------------------------------------------------------------------------
# Buckets de dados: raw, curated, logs — um conjunto por ambiente
# ---------------------------------------------------------------------------
module "data" {
  source   = "../modules/s3-bucket"
  for_each = local.data_buckets

  name          = each.value
  force_destroy = var.force_destroy

  # Sem versionamento: com expiração de 30 dias, versionar só acumularia
  # versões antigas que ninguém lê e que contam para a fatura.
  versioning = false

  # Num sandbox de estudo, dado bruto e checkpoint de streaming acumulam sem
  # ninguém perceber. 30 dias é suficiente para estudar e evita conta surpresa.
  expiration_days = 30
}

# ---------------------------------------------------------------------------
# S3 Tables: o "lakehouse" onde os workloads gravam as tabelas Iceberg
# ---------------------------------------------------------------------------
# Fica inline: é um recurso único, sem variação entre chamadas, e um módulo de
# uma linha só acrescentaria indireção.
resource "aws_s3tables_table_bucket" "lakehouse" {
  name = "dataeng-sandbox-lakehouse-${var.environment}"
}
