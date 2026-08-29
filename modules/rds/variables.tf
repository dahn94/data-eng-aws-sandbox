variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC — allowed to reach Postgres so that DMS in private subnets can connect"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "dataengsandbox"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "engine_version" {
  description = "PostgreSQL engine version. Precisa casar com a family do parameter group."
  type        = string
  default     = "17.5"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach Postgres on 5432 from outside the VPC (e.g. your IP as x.x.x.x/32). Empty = no external access."
  type        = list(string)
  default     = []
}
