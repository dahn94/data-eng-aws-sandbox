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

variable "ecr_repository_name" {
  description = "Nome do repositório ECR que guarda a imagem da Lambda"
  type        = string
  default     = "lambda-duckdb-sandbox"
}

variable "image_tag" {
  description = <<-EOT
    Tag da imagem a publicar na Lambda. Vazio = só o repositório ECR é criado
    (primeiro apply). Depois de rodar scripts/build_and_push.sh, preencha com a
    tag que ele imprimiu e aplique de novo.
  EOT
  type        = string
  default     = ""
}

variable "lakehouse_arn" {
  description = "ARN do bucket S3 Tables consultado. Vazio = montado a partir da conta, região e ambiente."
  type        = string
  default     = ""
}

variable "readable_buckets" {
  description = "Buckets S3 que a Lambda pode ler além do S3 Tables"
  type        = list(string)
  default     = []
}

variable "create_function_url" {
  description = "Cria uma Function URL (sempre com auth AWS_IAM). Deixe false se for invocar só pela API da Lambda."
  type        = bool
  default     = false
}

variable "allowed_origins" {
  description = "Origens permitidas no CORS da Function URL. ['*'] junto de credenciais é rejeitado pelos navegadores — liste origens explícitas."
  type        = list(string)
  default     = []
}
