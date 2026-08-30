resource "aws_security_group" "this" {
  name        = "${var.instance_name}-sg"
  description = "Security Group for ${var.instance_name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.instance_name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Acesso por SSM Session Manager: dispensa porta 22 aberta e key pair.
resource "aws_iam_role" "ssm" {
  name = "${var.instance_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.instance_name}-ssm-profile"
  role = aws_iam_role.ssm.name
}

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  key_name                    = var.key_name != "" ? var.key_name : null
  associate_public_ip_address = var.associate_public_ip
  iam_instance_profile        = aws_iam_instance_profile.ssm.name

  user_data                   = var.user_data != "" ? var.user_data : null
  user_data_replace_on_change = true

  vpc_security_group_ids = [aws_security_group.this.id]

  # IMDSv2 obrigatório: bloqueia o caminho clássico de roubo de credencial da
  # instance profile via SSRF.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  # Spot: mesma instância, capacidade ociosa, ~70% mais barata. `one-time` +
  # `terminate` mantém o recurso simples — sem requisição pendente sobrando
  # depois de um destroy. O custo é não poder parar a instância.
  dynamic "instance_market_options" {
    for_each = var.spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
        max_price                      = var.spot_max_price != "" ? var.spot_max_price : null
      }
    }
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = var.instance_name
  }
}
