variable "environment" {
  description = "Ambiente de implantação (dev, prod)"
  type        = string
  default     = "dev"
}

variable "network_state_bucket" {
  description = "S3 bucket holding platform/network's state. No default on purpose — it is your own bucket, set in envs/*.tfvars."
  type        = string
}

variable "network_state_key" {
  description = "S3 key of platform/network's state for this environment"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = <<-EOT
    De onde o SEU acesso vem, como `x.x.x.x/32`. Descubra com
    `curl -s https://checkip.amazonaws.com`.

    Vazio (o default) = nenhuma porta aberta, e o acesso é por SSM Session
    Manager, que não expõe nada na internet. Preencher abre SSH e as portas
    dos serviços (`service_ports`) apenas para estes blocos.

    Nunca coloque `0.0.0.0/0` aqui: Kafka, Schema Registry e OpenSearch sobem
    sem autenticação nenhuma neste laboratório. Expostos na internet, viram
    alvo de varredura automatizada em questão de horas.
  EOT
  type        = list(string)
  default     = []
}

variable "service_ports" {
  description = <<-EOT
    Portas dos serviços do `local-services`, abertas somente para
    `allowed_cidr_blocks`. O default cobre o caminho do
    `workloads/webevents-streaming`: Kafka externo, Schema Registry, Kafka
    Connect, kafka-ui, OpenSearch e Dashboards.
  EOT
  type        = map(number)
  default = {
    "kafka externo"         = 29092
    "schema registry"       = 8081
    "kafka connect"         = 8083
    "kafka-ui"              = 8080
    "opensearch"            = 9200
    "opensearch dashboards" = 5601
  }
}

variable "spot" {
  description = <<-EOT
    Compra a instância no mercado spot. É o que torna este laboratório barato:
    ~US$0,017/h contra ~US$0,067/h on-demand no mesmo t4g.large.

    O preço da troca é não poder parar a instância — só destruir e recriar — e
    aceitar que a AWS pode retomá-la com 2 minutos de aviso. Para um
    laboratório reconstruído pelo bootstrap, os dois são aceitáveis.
  EOT
  type        = bool
  default     = true
}

variable "instance_type" {
  description = <<-EOT
    Tipo da instância. O default é Graviton (ARM): `t4g.large` custa
    US$0,0171/h no spot contra US$0,0752/h de um t3a.large on-demand.

    Se trocar, mantenha a família `g` (t4g, m7g, c7g) — a AMI selecionada é
    arm64, e um tipo x86 não vai dar boot com ela. Se precisar de mais memória,
    `t4g.xlarge` (16 GB) sai a ~US$0,044/h no spot.
  EOT
  type        = string
  default     = "t4g.large"
}

variable "root_volume_size" {
  description = <<-EOT
    Tamanho do disco raiz em GB, a ~US$0,08/GB/mês. 30 GB é o suficiente para
    as imagens Docker do `local-services` mais folga de log. O disco morre com
    a instância (`delete_on_termination`), então ele não sobra cobrando depois
    de um destroy.
  EOT
  type        = number
  default     = 30
}

variable "key_name" {
  description = "Nome de um EC2 Key Pair já existente na sua conta, para SSH. Vazio = sem key pair (acesso só via SSM Session Manager)."
  type        = string
  default     = ""
}

variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-2"
}

variable "extra_ingress_rules" {
  description = "Portas adicionais a abrir (ex: 29092 para Kafka, 9200 para OpenSearch). Sempre restrinja o cidr_blocks ao seu IP."
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
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

variable "allow_from_vpc" {
  description = <<-EOT
    Abre as portas de `service_ports` para o CIDR da própria VPC. É o que
    permite ao job Glue de `workloads/webevents-streaming` alcançar o Kafka
    daqui, quando esse workload roda com `enable_vpc_connection = true`.

    Ligado por default porque não expõe nada na internet — só o que já está
    dentro da sua VPC alcança essas portas. Desligue se quiser a instância
    isolada até dela mesma.
  EOT
  type        = bool
  default     = true
}
