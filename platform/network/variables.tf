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

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas (uma por AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (uma por AZ)"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "AZs onde criar as subnets. Precisa casar com a região do provider."
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
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
