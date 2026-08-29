variable "environment" {
  description = "Environment name"
  type        = string
}

variable "source_endpoint_config" {
  description = "Source endpoint configuration. server_name must be a hostname only (no port)."
  type = object({
    endpoint_id   = string
    engine_name   = string
    server_name   = string
    port          = number
    database_name = string
    username      = string
    password      = string
  })
  sensitive = true
}

variable "target_s3_config" {
  description = "Target S3 configuration"
  type = object({
    bucket_name   = string
    bucket_folder = string
  })
}

variable "table_mappings" {
  description = "Table mappings for DMS replication (JSON string)"
  type        = string
}

variable "replication_subnet_group_id" {
  description = "ID of the existing DMS replication subnet group"
  type        = string
}

variable "replication_instance_class" {
  description = "Classe da instância de replicação. dms.t3.micro custa ~US$0,036/h (~US$28/mês rodando 24/7) e não pode ser parada, só destruída."
  type        = string
  default     = "dms.t3.micro"
}

variable "allocated_storage" {
  description = "Armazenamento da instância de replicação em GB"
  type        = number
  default     = 20
}

variable "create_vpc_role" {
  description = <<-EOT
    Cria a role `dms-vpc-role`, exigida pelo DMS para gerenciar ENIs. É única
    por conta AWS: se você já a tem (por outro projeto ou por ter usado o
    console do DMS antes), deixe false para não conflitar.
  EOT
  type        = bool
  default     = true
}
