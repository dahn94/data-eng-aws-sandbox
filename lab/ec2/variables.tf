variable "environment" {
  description = "Ambiente de implantação (dev, prod)"
  type        = string
  default     = "dev"
}

variable "network_state_bucket" {
  description = "S3 bucket holding platform/network's state. No default on purpose — it is your own bucket, set in envs/*.tfvars."
  type        = string
}

variable "network_state_key" {
  description = "S3 key of platform/network's state for this environment"
  type        = string
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the instance (e.g. your IP as x.x.x.x/32). Empty = no SSH access — use SSM Session Manager instead."
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "Tipo da instância. O default é modesto de propósito: veja a seção de custo no README antes de aumentar."
  type        = string
  default     = "t3a.large"
}

variable "root_volume_size" {
  description = "Tamanho do disco raiz em GB. Cada GB de gp3 custa ~US$0,08/mês, então 500 GB são ~US$40/mês só de disco."
  type        = number
  default     = 100
}

variable "key_name" {
  description = "Nome de um EC2 Key Pair já existente na sua conta, para SSH. Vazio = sem key pair (acesso só via SSM Session Manager)."
  type        = string
  default     = ""
}

variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-2"
}

variable "extra_ingress_rules" {
  description = "Portas adicionais a abrir (ex: 29092 para Kafka, 9200 para OpenSearch). Sempre restrinja o cidr_blocks ao seu IP."
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
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
