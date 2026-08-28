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

variable "bucket_prefix" {
  description = <<-EOT
    Prefixo único dos buckets S3 deste projeto. Nomes de bucket são globais na
    AWS inteira, então use algo seu (ex: seu usuário do GitHub). Sem default de
    propósito — rode `./scripts/set-bucket-prefix.sh <seu-prefixo>` na raiz do
    repositório para preencher isto e os arquivos de backend de uma vez.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.bucket_prefix))
    error_message = "bucket_prefix deve ter entre 3 e 32 caracteres, só minúsculas, números e hífens."
  }
}

variable "force_destroy" {
  description = "Permite que `terraform destroy` apague buckets com objetos dentro. true é o razoável num sandbox de estudo."
  type        = bool
  default     = true
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
