data "terraform_remote_state" "network" {
  backend = "s3"
  config = merge({
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.region
  }, local.localstack_state_config)
}

# AMI resolvida na hora, em vez de um ID fixo que expira e só existe numa região.
# arm64 porque a instância é Graviton: uma AMI x86 simplesmente não dá boot num
# t4g. Se você trocar instance_type para uma família x86, troque aqui também.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

module "ec2_instance" {
  source = "../../modules/ec2"

  ami_id              = data.aws_ami.amazon_linux_2023.id
  instance_type       = var.instance_type
  root_volume_size    = var.root_volume_size
  subnet_id           = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  key_name            = var.key_name
  associate_public_ip = true
  instance_name       = "dataeng-sandbox-streaming-host-${var.environment}"

  spot = var.spot

  user_data = file("${path.module}/scripts/bootstrap/bootstrap.sh")

  # Só o que você declarar entra. Com allowed_cidr_blocks vazio (o default) não
  # há regra de entrada nenhuma — o acesso é por SSM Session Manager, que não
  # expõe porta nenhuma na internet:
  #   aws ssm start-session --target <instance-id>
  #
  # Para alcançar as UIs sem abrir nada, use encaminhamento de porta pelo SSM:
  #   aws ssm start-session --target <id> \
  #     --document-name AWS-StartPortForwardingSession \
  #     --parameters "portNumber=5601,localPortNumber=5601"
  ingress_rules = concat(
    length(var.allowed_cidr_blocks) > 0 ? [{
      description = "SSH from allowed CIDRs"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }] : [],
    length(var.allowed_cidr_blocks) > 0 ? [
      for nome, porta in var.service_ports : {
        description = nome
        from_port   = porta
        to_port     = porta
        protocol    = "tcp"
        cidr_blocks = var.allowed_cidr_blocks
      }
    ] : [],
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
