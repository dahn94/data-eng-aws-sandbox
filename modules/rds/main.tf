locals {
  # O parameter group precisa de nome curto e estável; o resto herda var.name.
  pg_name = "${var.name}-pg"
}

# Replicação lógica é pré-requisito de CDC — tanto pelo DMS quanto pelo
# Debezium. Sem rds.logical_replication = 1 o full-load funciona e o CDC fica
# parado para sempre, sem erro claro. Exige reboot: o parâmetro é estático.
resource "aws_db_parameter_group" "postgres" {
  family = "postgres17"
  name   = local.pg_name

  dynamic "parameter" {
    for_each = var.enable_logical_replication ? [1] : []
    content {
      name         = "rds.logical_replication"
      value        = "1"
      apply_method = "pending-reboot"
    }
  }

  # O Debezium/DMS seguram um replication slot por task. O default (10) é
  # suficiente, mas deixar explícito evita esbarrar no limite sem entender.
  parameter {
    name         = "max_replication_slots"
    value        = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_wal_senders"
    value        = "10"
    apply_method = "pending-reboot"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.public_subnet_ids

  tags = {
    Name = "${var.name}-subnet-group"
  }
}

resource "aws_security_group" "postgres" {
  name_prefix = "${var.name}-"
  description = "Postgres access for the DataEng sandbox"
  vpc_id      = var.vpc_id

  # Acesso de fora da VPC (sua máquina). Vazio = ninguém entra de fora.
  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Postgres from allowed external CIDRs"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  # Acesso de dentro da VPC. É isto que permite o DMS, que roda em subnet
  # privada, alcançar o banco — sem esta regra o CDC nunca conecta.
  ingress {
    description = "Postgres from inside the VPC (DMS, EC2)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  parameter_group_name   = aws_db_parameter_group.postgres.name
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  # Público de propósito: o objetivo do sandbox é você conectar da sua máquina
  # com um cliente SQL. O que realmente protege o banco é o security group
  # acima — mantenha allowed_cidr_blocks no seu IP, nunca em 0.0.0.0/0.
  publicly_accessible = true

  # Sandbox: sem snapshot final e sem proteção contra delete, para que
  # `terraform destroy` termine sem intervenção manual no fim do estudo.
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0

  # O parameter group novo só entra em vigor depois de um reboot; aplicar
  # imediatamente evita que o CDC fique quebrado até a janela de manutenção.
  apply_immediately = true

  tags = {
    Name = var.name
  }
}
