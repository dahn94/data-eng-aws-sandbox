variable "ami_id" {
  description = "AMI ID da instância"
  type        = string
}

variable "instance_type" {
  description = "Tipo da instância"
  type        = string
}

variable "subnet_id" {
  description = "Subnet onde a instância será criada"
  type        = string
}

variable "vpc_id" {
  description = "VPC onde o Security Group será criado"
  type        = string
}

variable "key_name" {
  description = "Nome de um EC2 Key Pair existente. Vazio = sem key pair; use SSM Session Manager."
  type        = string
  default     = ""
}

variable "associate_public_ip" {
  description = "Se deve associar um IP público"
  type        = bool
  default     = false
}

variable "instance_name" {
  description = "Nome da instância, usado como prefixo dos recursos"
  type        = string
}

variable "root_volume_size" {
  description = "Tamanho do disco raiz em GB"
  type        = number
  default     = 100
}

variable "ingress_rules" {
  description = <<-EOT
    Regras de entrada do Security Group. O default é lista vazia de propósito:
    nada entra a menos que você declare explicitamente. A versão anterior
    abria 22, 3000 e 8000 para 0.0.0.0/0 por default.
  EOT
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "user_data" {
  description = "Script de bootstrap executado no boot"
  type        = string
  default     = ""
}
