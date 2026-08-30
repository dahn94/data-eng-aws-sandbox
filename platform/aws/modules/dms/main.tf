# IAM role usada pelo endpoint S3 de destino
resource "aws_iam_role" "dms_s3_target" {
  name = "dms-s3-target-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "dms-s3-target-${var.environment}"
  }
}

# Escopo restrito ao bucket de destino. A política gerenciada
# AmazonDMSRedshiftS3Role, comum em tutoriais, dá acesso a S3 inteiro.
resource "aws_iam_policy" "dms_s3_target" {
  name        = "dms-s3-target-${var.environment}"
  description = "Write access limited to the raw bucket used by DMS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutObjectTagging",
        ]
        Resource = ["arn:aws:s3:::${var.target_s3_config.bucket_name}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = ["arn:aws:s3:::${var.target_s3_config.bucket_name}"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dms_s3_target" {
  policy_arn = aws_iam_policy.dms_s3_target.arn
  role       = aws_iam_role.dms_s3_target.name
}

# IAM Role exigida pelo DMS para gerenciar ENIs na VPC.
# É uma role de nome fixo e única por conta — por isso não leva sufixo de
# ambiente e é opcional: se já existe na conta, deixe create_vpc_role = false.
resource "aws_iam_role" "dms_vpc_role" {
  count = var.create_vpc_role ? 1 : 0
  name  = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "dms-vpc-role"
  }
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role" {
  count      = var.create_vpc_role ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
  role       = aws_iam_role.dms_vpc_role[0].name
}

# Source Endpoint (PostgreSQL)
resource "aws_dms_endpoint" "source" {
  endpoint_id   = var.source_endpoint_config.endpoint_id
  endpoint_type = "source"
  engine_name   = var.source_endpoint_config.engine_name

  # server_name aceita apenas o hostname. O output `endpoint` do RDS vem no
  # formato host:porta e faz o endpoint subir quebrado — use `address`.
  server_name   = var.source_endpoint_config.server_name
  port          = var.source_endpoint_config.port
  database_name = var.source_endpoint_config.database_name
  username      = var.source_endpoint_config.username
  password      = var.source_endpoint_config.password

  tags = {
    Name = "dms-source-endpoint-${var.environment}"
  }
}

# Target Endpoint (S3)
resource "aws_dms_endpoint" "target" {
  endpoint_id   = "s3-target-${var.environment}"
  endpoint_type = "target"
  engine_name   = "s3"

  s3_settings {
    bucket_name             = var.target_s3_config.bucket_name
    bucket_folder           = var.target_s3_config.bucket_folder
    compression_type        = "GZIP"
    data_format             = "parquet"
    service_access_role_arn = aws_iam_role.dms_s3_target.arn
  }

  tags = {
    Name = "dms-target-endpoint-${var.environment}"
  }
}

resource "aws_dms_replication_instance" "main" {
  replication_instance_id     = "dms-instance-${var.environment}"
  replication_instance_class  = var.replication_instance_class
  allocated_storage           = var.allocated_storage
  replication_subnet_group_id = var.replication_subnet_group_id
  publicly_accessible         = false

  tags = {
    Name = "dms-instance-${var.environment}"
  }

  depends_on = [aws_iam_role_policy_attachment.dms_vpc_role]
}

resource "aws_dms_replication_task" "main" {
  replication_task_id      = "postgres-to-s3-${var.environment}"
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn
  migration_type           = "full-load-and-cdc"
  table_mappings           = var.table_mappings

  tags = {
    Name = "dms-replication-task-${var.environment}"
  }

  depends_on = [
    aws_iam_role_policy_attachment.dms_s3_target,
    aws_iam_role_policy_attachment.dms_vpc_role,
  ]
}
