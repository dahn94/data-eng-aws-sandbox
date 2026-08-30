variable "name" {
  description = "Nome do bucket. Global na AWS inteira, então já vem com o prefixo de quem chama."
  type        = string
}

variable "force_destroy" {
  description = "Permite destruir o bucket com objetos dentro. Verdadeiro só faz sentido em sandbox."
  type        = bool
  default     = false
}

variable "versioning" {
  description = <<-EOT
    Liga versionamento. É o que permite recuperar um objeto sobrescrito — no
    bucket de configs, um `terraform.tfstate` corrompido.

    Nos buckets de dados fica desligado de propósito: com expiração de 30 dias,
    versionar só acumularia versões antigas que ninguém vai ler e que contam
    para a fatura.
  EOT
  type        = bool
  default     = false
}

variable "expiration_days" {
  description = <<-EOT
    Expira objetos com esta idade. Zero (o default) = sem ciclo de vida.

    Num sandbox de estudo, dado bruto e checkpoint de streaming acumulam sem
    ninguém perceber. Um teto de dias evita conta surpresa.
  EOT
  type        = number
  default     = 0
}

variable "abort_multipart_days" {
  description = "Descarta upload multipart interrompido depois de N dias. Só vale quando expiration_days > 0."
  type        = number
  default     = 7
}
