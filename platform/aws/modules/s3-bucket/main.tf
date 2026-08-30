# Um bucket S3 com o que este repositório considera o mínimo decente:
# criptografia em repouso, acesso público bloqueado, e — quando pedido —
# versionamento e ciclo de vida.
#
# Existe porque o `foundation` tinha 106 linhas de S3 inline enquanto o
# `network` era uma casca fina sobre `modules/vpc`. Duas convenções no mesmo
# nível, sem motivo.

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloqueio de acesso público em todas as quatro dimensões. Não é configurável de
# propósito: um bucket de lake exposto é o acidente mais caro possível aqui.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  count = var.versioning ? 1 : 0

  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.expiration_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expira-objetos-antigos"
    status = "Enabled"

    filter {}

    expiration {
      days = var.expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_multipart_days
    }
  }
}
