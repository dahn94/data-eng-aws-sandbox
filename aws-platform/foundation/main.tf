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
resource "aws_s3_bucket" "configs" {
  bucket        = local.configs_bucket
  force_destroy = var.force_destroy
}

# Versionamento é o que permite recuperar um tfstate corrompido/sobrescrito.
resource "aws_s3_bucket_versioning" "configs" {
  bucket = aws_s3_bucket.configs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "configs" {
  bucket = aws_s3_bucket.configs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "configs" {
  bucket                  = aws_s3_bucket.configs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Buckets de dados: raw, curated, logs — um conjunto por ambiente
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "data" {
  for_each = local.data_buckets

  bucket        = each.value
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  for_each = aws_s3_bucket.data

  bucket = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  for_each = aws_s3_bucket.data

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Num sandbox de estudo, dado bruto e checkpoint de streaming acumulam sem
# ninguém perceber. 30 dias é suficiente para estudar e evita conta surpresa.
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  for_each = aws_s3_bucket.data

  bucket = each.value.id

  rule {
    id     = "expira-objetos-antigos"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# S3 Tables: o "lakehouse" onde as pipelines gravam as tabelas Iceberg
# ---------------------------------------------------------------------------
resource "aws_s3tables_table_bucket" "lakehouse" {
  name = "dataeng-sandbox-lakehouse-${var.environment}"
}
