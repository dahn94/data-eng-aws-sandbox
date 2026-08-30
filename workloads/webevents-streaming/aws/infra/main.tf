locals {
  jar_dir = "jars"
  jar_files = [
    "${local.jar_dir}/spark-sql-kafka-0-10_2.12-3.3.4.jar",
    "${local.jar_dir}/spark-avro_2.12-3.3.4.jar",
    "${local.jar_dir}/opensearch-spark-30_2.12-1.3.0.jar",
    "${local.jar_dir}/kafka-clients-3.5.2.jar",
    "${local.jar_dir}/commons-pool2-2.12.1.jar",
  ]

  checkpoint_path = "s3://${var.s3_bucket_logs}/spark-checkpoints/${var.environment}/webevents-streaming"
}

# A senha do OpenSearch vai para o Secrets Manager, não para os argumentos do
# job: argumento de Glue job fica em texto claro no console e é legível por
# qualquer principal com glue:GetJob. O job recebe só o ARN.
resource "aws_secretsmanager_secret" "opensearch" {
  name                    = "dataeng-sandbox/${var.environment}/opensearch"
  description             = "Credenciais do OpenSearch usadas pelo job de streaming"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "opensearch" {
  secret_id = aws_secretsmanager_secret.opensearch.id
  secret_string = jsonencode({
    username = "admin"
    password = var.opensearch_password
  })
}

# ---------------------------------------------------------------------------
# Job dentro da VPC (opcional, desligado por padrão)
# ---------------------------------------------------------------------------
#
# Sem isto, o job Glue roda na rede gerenciada da AWS e sai por endereços que
# você não consegue prever — então não existe security group restrito que o
# deixe alcançar o Kafka do host de streaming. A única alternativa seria abrir
# a porta 29092 para 0.0.0.0/0, e o Kafka deste laboratório roda em PLAINTEXT,
# sem autenticação nenhuma.
#
# Com isto, o job ganha ENIs numa subnet privada da sua VPC e fala com o host
# pelo IP privado. Nada precisa ser exposto.
#
# O preço: dentro da VPC o job perde o acesso à internet. S3 continua de graça
# pelo Gateway Endpoint que platform/aws/network já cria, mas o Secrets Manager —
# de onde o script lê a senha do OpenSearch — precisa de um Interface Endpoint.

data "terraform_remote_state" "network" {
  count   = local.needs_network ? 1 : 0
  backend = "s3"
  config = {
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.region
  }
}

locals {
  # Os dois interruptores precisam da VPC: o host vive nela, e o job entra nela.
  needs_network = var.enable_vpc_connection || var.enable_streaming_host
  vpc_enabled   = var.enable_vpc_connection
  # Uma subnet só: a connection do Glue vive numa única AZ, e manter o endpoint
  # na mesma AZ evita pagar por um segundo endpoint sem ganho nenhum.
  glue_subnet_id = local.vpc_enabled ? data.terraform_remote_state.network[0].outputs.private_subnet_ids[0] : null
  glue_vpc_id    = local.vpc_enabled ? data.terraform_remote_state.network[0].outputs.vpc_id : null

  host_enabled = var.enable_streaming_host

  # O endereço que o job usa. Se este workload criou o host, ele já sabe o
  # endereço — e sabe qual dos dois: pelo IP privado quando o job entra pela
  # VPC, pelo público quando não entra. Só cai no var.streaming_host quando o
  # host é seu, de fora daqui.
  resolved_streaming_host = (
    local.host_enabled
    ? (local.vpc_enabled ? module.streaming_host[0].private_ip : module.streaming_host[0].public_ip)
    : var.streaming_host
  )
}

# ---------------------------------------------------------------------------
# O host de streaming (opcional)
# ---------------------------------------------------------------------------
#
# Kafka, Schema Registry e OpenSearch precisam rodar em algum lugar que o job
# Glue alcance. No ambiente `local` esse lugar é a sua máquina. Contra a AWS,
# precisa ser uma instância — e este workload é dono dela, porque é o único que
# a usa.

module "streaming_host" {
  count  = local.host_enabled ? 1 : 0
  source = "../../../../modules/ec2"

  instance_name       = "dataeng-sandbox-streaming-host-${var.environment}"
  ami_id              = data.aws_ami.streaming_host[0].id
  instance_type       = var.streaming_host_instance_type
  root_volume_size    = var.streaming_host_volume_size
  spot                = var.streaming_host_spot
  subnet_id           = data.terraform_remote_state.network[0].outputs.public_subnet_ids[0]
  vpc_id              = data.terraform_remote_state.network[0].outputs.vpc_id
  associate_public_ip = true

  user_data = file("${path.module}/../../scripts/bootstrap/bootstrap.sh")

  # Nada entra por default. O que entra:
  #   - o seu IP, se você declarar, para alcançar as UIs direto
  #   - o CIDR da VPC, que é por onde o job Glue chega quando roda dentro dela
  ingress_rules = concat(
    [
      for nome, porta in var.streaming_host_service_ports : {
        description = nome
        from_port   = porta
        to_port     = porta
        protocol    = "tcp"
        cidr_blocks = var.streaming_host_allowed_cidr_blocks
      } if length(var.streaming_host_allowed_cidr_blocks) > 0
    ],
    [
      for nome, porta in var.streaming_host_service_ports : {
        description = "${nome} (de dentro da VPC)"
        from_port   = porta
        to_port     = porta
        protocol    = "tcp"
        cidr_blocks = [data.terraform_remote_state.network[0].outputs.vpc_cidr]
      }
    ],
  )
}

# arm64 porque a instância é Graviton: uma AMI x86 não dá boot num t4g.
data "aws_ami" "streaming_host" {
  count       = local.host_enabled ? 1 : 0
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

# O Glue exige que o security group da connection libere ele mesmo: as ENIs do
# job conversam entre si. Sem esta regra a connection falha na validação, com
# uma mensagem que não diz isso.
resource "aws_security_group" "glue" {
  count = local.vpc_enabled ? 1 : 0

  name        = "dataeng-sandbox-webevents-streaming-glue-${var.environment}"
  description = "ENIs do job Glue de streaming dentro da VPC"
  vpc_id      = local.glue_vpc_id

  tags = {
    Name = "dataeng-sandbox-webevents-streaming-glue-${var.environment}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "glue_self" {
  count = local.vpc_enabled ? 1 : 0

  security_group_id            = aws_security_group.glue[0].id
  description                  = "Exigido pelo Glue: as ENIs do job falam entre si"
  referenced_security_group_id = aws_security_group.glue[0].id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "glue_all" {
  count = local.vpc_enabled ? 1 : 0

  security_group_id = aws_security_group.glue[0].id
  description       = "Saída para o host de streaming, o S3 e o endpoint do Secrets Manager"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Interface Endpoint do Secrets Manager: é a única coisa fora da VPC que o
# script precisa alcançar. É também o único item desta seção que cobra parado.
resource "aws_security_group" "secretsmanager_endpoint" {
  count = local.vpc_enabled ? 1 : 0

  name        = "dataeng-sandbox-webevents-streaming-smep-${var.environment}"
  description = "Interface Endpoint do Secrets Manager"
  vpc_id      = local.glue_vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "secretsmanager_from_glue" {
  count = local.vpc_enabled ? 1 : 0

  security_group_id            = aws_security_group.secretsmanager_endpoint[0].id
  description                  = "HTTPS a partir das ENIs do job"
  referenced_security_group_id = aws_security_group.glue[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_endpoint" "secretsmanager" {
  count = local.vpc_enabled ? 1 : 0

  vpc_id              = local.glue_vpc_id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [local.glue_subnet_id]
  security_group_ids  = [aws_security_group.secretsmanager_endpoint[0].id]
  private_dns_enabled = true

  tags = {
    Name = "dataeng-sandbox-webevents-streaming-secretsmanager-${var.environment}"
  }
}

resource "aws_glue_connection" "vpc" {
  count = local.vpc_enabled ? 1 : 0

  name            = "dataeng-sandbox-webevents-streaming-${var.environment}"
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = data.aws_subnet.glue[0].availability_zone
    subnet_id              = local.glue_subnet_id
    security_group_id_list = [aws_security_group.glue[0].id]
  }
}

data "aws_subnet" "glue" {
  count = local.vpc_enabled ? 1 : 0
  id    = local.glue_subnet_id
}

module "glue_jobs_streaming" {
  source = "../../../../modules/glue-job"

  project_name       = "dataeng-sandbox-webevents-streaming"
  environment        = var.environment
  region             = var.region
  s3_bucket_scripts  = var.s3_bucket_scripts
  data_buckets       = [var.s3_bucket_raw, var.s3_bucket_logs]
  scripts_local_path = "../../scripts"

  # gluestreaming, não glueetl: um job de Structured Streaming roda
  # indefinidamente e morreria no timeout de um job em lote.
  job_type = "streaming"

  job_scripts = {
    "dataeng-sandbox-webevents-streaming-kafka-opensearch" = "dataeng-sandbox-webevents-streaming-kafka-opensearch.py",
  }

  connections = local.vpc_enabled ? [aws_glue_connection.vpc[0].name] : []

  jar_files  = local.jar_files
  extra_jars = join(",", [for j in local.jar_files : "s3://${var.s3_bucket_scripts}/jars/${basename(j)}"])

  readable_secret_arns = [aws_secretsmanager_secret.opensearch.arn]

  worker_type       = "G.025X"
  number_of_workers = 2
  max_retries       = 0
  glue_version      = "4.0"

  additional_arguments = {
    "--user-jars-first"       = "true"
    "--OPENSEARCH_SECRET_ARN" = aws_secretsmanager_secret.opensearch.arn
    "--STREAMING_HOST"        = local.resolved_streaming_host
    "--KAFKA_TOPIC"           = var.kafka_topic
    "--OPENSEARCH_INDEX"      = "${var.opensearch_index}-${var.environment}"
    "--CHECKPOINT_PATH"       = local.checkpoint_path
  }
}
