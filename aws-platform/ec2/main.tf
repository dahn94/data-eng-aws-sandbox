data "terraform_remote_state" "network" {
  backend = "s3"
  config = merge({
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.region
  }, local.localstack_state_config)
}

# AMI resolvida na hora, em vez de um ID fixo que expira e só existe numa região.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

module "ec2_instance" {
  source = "../modules/ec2"

  ami_id              = data.aws_ami.amazon_linux_2023.id
  instance_type       = var.instance_type
  root_volume_size    = var.root_volume_size
  subnet_id           = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  key_name            = var.key_name
  associate_public_ip = true
  instance_name       = "dataeng-sandbox-ec2-${var.environment}"

  user_data = file("${path.module}/scripts/bootstrap/ec2_bootstrap.sh")

  # Só o que você declarar entra. Com ssh_allowed_cidr_blocks vazio (o default)
  # não há regra de entrada nenhuma — o acesso é por SSM Session Manager:
  #   aws ssm start-session --target <instance-id>
  ingress_rules = concat(
    length(var.ssh_allowed_cidr_blocks) > 0 ? [{
      description = "SSH from allowed CIDRs"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidr_blocks
    }] : [],
    [
      for rule in var.extra_ingress_rules : {
        description = rule.description
        from_port   = rule.from_port
        to_port     = rule.to_port
        protocol    = rule.protocol
        cidr_blocks = rule.cidr_blocks
      }
    ],
  )
}
