variable "environment" {
  description = "Ambiente de implantação (dev, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-2"
}

variable "s3_bucket_raw" {
  description = "Bucket S3 com os dados brutos (criado por platform/foundation)"
  type        = string
}

variable "s3_bucket_logs" {
  description = "Bucket S3 onde o Spark Structured Streaming grava o checkpoint (criado por platform/foundation)"
  type        = string
}

variable "s3_bucket_scripts" {
  description = "Bucket S3 que guarda os scripts Glue e os jars (criado por platform/foundation)"
  type        = string
}

variable "opensearch_password" {
  description = <<-EOT
    Senha do usuário 'admin' do OpenSearch. Não vira argumento do job Glue (que
    ficaria em texto claro no console): é gravada num secret do Secrets Manager,
    e o job recebe apenas o ARN do secret. Sem default de propósito — passe via
    -var, TF_VAR_opensearch_password ou um *.auto.tfvars não versionado.
  EOT
  type        = string
  sensitive   = true
}

variable "streaming_host" {
  description = <<-EOT
    Endereço onde Kafka, Schema Registry e OpenSearch respondem, visto de onde o
    job Glue roda.

    Com `enable_streaming_host = true` este campo é ignorado: o workload cria o
    host e já sabe o endereço — o privado quando o job entra pela VPC, o público
    quando não entra.

    Preencha só quando o host for seu, criado fora daqui. No ambiente `local`
    é `host.docker.internal`.
  EOT
  type        = string
  default     = ""
}

variable "kafka_topic" {
  description = "Tópico Kafka lido pelo job. Deve casar com topic.prefix do connector Debezium: <prefix>.<schema>.<tabela>."
  type        = string
  default     = "ecommerce.public.web_events"
}

variable "opensearch_index" {
  description = "Índice do OpenSearch onde os eventos são gravados"
  type        = string
  default     = "web_events"
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

variable "enable_vpc_connection" {
  description = <<-EOT
    Faz o job Glue rodar DENTRO da VPC, por uma `aws_glue_connection` do tipo
    NETWORK. É o que permite alcançar o Kafka do host de streaming pelo IP
    privado — sem isso, o job sai por IPs imprevisíveis da AWS e a única forma
    de deixá-lo entrar seria expor o Kafka (que roda em PLAINTEXT, sem
    autenticação) na internet aberta.

    **Custa dinheiro, e por isso nasce desligado.** Dentro da VPC o job perde o
    acesso à internet: ele alcança S3 pelo Gateway Endpoint (gratuito), mas
    precisa de um Interface Endpoint para o Secrets Manager, de onde lê a senha
    do OpenSearch. Um endpoint numa AZ custa cerca de US$0,01/h, ~US$7/mês
    parado, mais o tráfego processado.

    Ligado, este workload passa a depender de `platform/network`.
  EOT
  type        = bool
  default     = false
}

variable "network_state_bucket" {
  description = "S3 bucket com o state de platform/network. Só é lido quando enable_streaming_host ou enable_vpc_connection estão ligados."
  type        = string
  default     = ""
}

variable "network_state_key" {
  description = "S3 key do state de platform/network para este ambiente. Só é lido quando enable_streaming_host ou enable_vpc_connection estão ligados."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Host de streaming: a máquina que hospeda Kafka, Schema Registry e OpenSearch
# ---------------------------------------------------------------------------
#
# Este workload é dono dela, pela mesma regra que faz zero-etl, incremental-mv e
# data-sharing serem donos de cada Redshift: o workload possui a infraestrutura
# que usa, e o que não se duplica é código (aqui, ../../modules/ec2).
#
# Nenhum outro workload precisa dela — o job Glue de streaming é o único
# consumidor que existe.

variable "enable_streaming_host" {
  description = <<-EOT
    Cria uma EC2 para hospedar `local-services/streaming-cdc` e
    `local-services/search-opensearch` dentro da AWS.

    Existe por um motivo só: o job Glue roda na AWS e não alcança o Docker da
    sua máquina. Rodando este workload no ambiente `local` (LocalStack), job e
    contêineres ficam juntos e nada disto é necessário — deixe desligado.

    Desligado por default porque é o único recurso deste workload que cobra por
    tempo ligado.
  EOT
  type        = bool
  default     = false
}

variable "streaming_host_instance_type" {
  description = <<-EOT
    Tipo da instância do host. O default é Graviton: `t4g.large` custa
    US$0,0171/h no spot, contra US$0,0752/h de um t3a.large on-demand.

    Mantenha a família `g` (t4g, m7g, c7g) — a AMI selecionada é arm64 e um
    tipo x86 não dá boot com ela. Se 8 GB apertarem com a pilha inteira,
    `t4g.xlarge` (16 GB) sai a ~US$0,044/h no spot.
  EOT
  type        = string
  default     = "t4g.large"
}

variable "streaming_host_volume_size" {
  description = "Disco raiz do host em GB, a ~US$0,08/GB/mês. 30 GB cobrem as imagens Docker com folga. Morre junto com a instância."
  type        = number
  default     = 30
}

variable "streaming_host_spot" {
  description = <<-EOT
    Compra o host no mercado spot: ~US$0,017/h contra ~US$0,067/h on-demand.

    Em troca, a instância não pode ser parada (requisição one-time, como o DMS)
    e a AWS pode retomá-la com 2 minutos de aviso. Para um host reconstruído
    pelo bootstrap, os dois são aceitáveis.
  EOT
  type        = bool
  default     = true
}

variable "streaming_host_allowed_cidr_blocks" {
  description = <<-EOT
    De onde o SEU acesso ao host vem, como `x.x.x.x/32`. Descubra com
    `curl -s https://checkip.amazonaws.com`.

    Vazio (o default) = nenhuma porta aberta na internet; o acesso é por SSM
    Session Manager, inclusive as UIs, por encaminhamento de porta.

    Nunca use `0.0.0.0/0`: o Kafka deste laboratório roda em PLAINTEXT, sem
    autenticação nenhuma.
  EOT
  type        = list(string)
  default     = []
}

variable "streaming_host_service_ports" {
  description = "Portas dos serviços do host, abertas para streaming_host_allowed_cidr_blocks e para o CIDR da VPC."
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
