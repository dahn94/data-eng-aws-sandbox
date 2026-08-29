# workloads/webevents-streaming

Job Glue de **streaming** que lê o CDC de `web_events` do Kafka (formato Avro
do Debezium), limpa os dados e grava no OpenSearch em tempo real.

## Pré-requisitos

1. **`platform/foundation` aplicado** — buckets de scripts e de logs.
2. **Os jars baixados** — `./scripts/fetch-jars.sh` na raiz. São 5 jars
   (Kafka, Avro, OpenSearch para Spark) que o Terraform envia ao S3.
3. **Kafka, Schema Registry e OpenSearch alcançáveis pelo job**, com o
   endereço em `streaming_host`. Como isso funciona depende de onde o job roda
   — veja "Onde o job roda" logo abaixo. É o pré-requisito mais incômodo deste
   workload, e o único que não se resolve com `terraform apply`.
4. **O connector Debezium registrado**, publicando no tópico
   `ecommerce.public.web_events` — veja `local-services/streaming-cdc`.

## Aplicar

```bash
cd workloads/webevents-streaming
terraform init -backend-config=backends/develop.hcl
export TF_VAR_opensearch_password='a-senha-do-admin-do-opensearch'
terraform apply -var-file=envs/develop.tfvars \
  -var="streaming_host=<endereco-do-host-de-streaming>"
```

Substitua também o `streaming_host = "CHANGEME.exemplo.invalid"` em
`envs/*.tfvars` se preferir fixá-lo.

## Onde o job roda

O job Glue precisa alcançar um Kafka que roda em `PLAINTEXT`, sem autenticação
nenhuma. Isso torna a pergunta "de onde o job sai" uma decisão de segurança,
não de conveniência. Há três caminhos, e eles não são equivalentes.

### 1. Ambiente `local` — o mais simples

Job e serviços na mesma máquina, via LocalStack. `streaming_host` é
`host.docker.internal` e não há mais nada a resolver. É o caminho recomendado
para estudar o comportamento do streaming.

### 2. Contra a AWS, com o job DENTRO da VPC — o recomendado

```hcl
enable_streaming_host = true
enable_vpc_connection = true
```

Não há endereço para preencher: o workload cria o host e sabe o IP dele. O
`streaming_host` só existe para o caso de o host ser seu, criado fora daqui.

Uma `aws_glue_connection` do tipo `NETWORK` dá ao job ENIs numa subnet privada
da sua VPC. Ele fala com o host de streaming pelo IP **privado**, e nada
precisa estar exposto na internet.

**O que isso custa.** Dentro da VPC o job perde o acesso à internet. O S3
continua gratuito pelo Gateway Endpoint que o `platform/network` já cria, mas o
script lê a senha do OpenSearch do Secrets Manager em runtime — e isso passa a
exigir um **Interface Endpoint**, que cobra cerca de **US$0,01/h (~US$7/mês)
mesmo parado**, mais o tráfego processado. O endpoint é criado numa AZ só, a
mesma da connection, justamente para não pagar dobrado.

É por isso que `enable_vpc_connection` nasce **desligado**: é o único recurso
deste workload que cobra sem ninguém rodar nada.

### 3. Contra a AWS, com o job FORA da VPC — não faça

É o comportamento default se você não ligar a chave acima. O job sai por
endereços da AWS que ninguém consegue prever, então a única forma de deixá-lo
entrar é abrir a porta 29092 do Kafka para `0.0.0.0/0`.

Kafka em PLAINTEXT na internet aberta é encontrado por varredura automatizada
em horas. Não há CIDR intermediário que resolva: ou o job entra pela VPC, ou o
Kafka fica exposto.

Iniciar o job:

```bash
aws glue start-job-run --job-name "$(terraform output -json glue_job_names | jq -r '.[]')"
```

## Como a senha do OpenSearch é tratada

Ela **não** vira argumento do job: argumento de Glue job fica em texto claro no
console e é legível por qualquer principal com `glue:GetJob`. O Terraform grava
a senha num secret do Secrets Manager e passa só o ARN ao job, que busca o
valor em runtime. A role do job só pode ler esse secret específico.

## Por que `gluestreaming`

O módulo `glue-job` recebe `job_type = "streaming"`, o que muda o `command.name`
do job para `gluestreaming` e remove o `timeout`. Um job de Structured
Streaming registrado como `glueetl` roda até bater o timeout e morre — parece
um bug intermitente e é só configuração.

## Checkpoint

Fica em `s3://<prefixo>-lake-logs-<amb>/spark-checkpoints/<amb>/webevents-streaming`.
Para reprocessar tudo do começo, apague esse caminho antes de reiniciar o job
— senão o Spark retoma do offset guardado.

## Custo

Um job de streaming **fica rodando**: 2 workers `G.025X` ≈ US$0,088/hora, ou
~US$64/mês se ficar ligado o mês inteiro. Pare o job quando terminar a sessão:

```bash
aws glue batch-stop-job-run --job-name <nome> --job-run-ids <id>
```

## Requisitos e decisões

Os requisitos não-funcionais deste fluxo — garantia de entrega, offsets,
latência, custo enquanto roda — estão em [`nfr.md`](nfr.md).

| # | Problema |
|---|---|
| [0001](adr/0001-onde-descartar-dado-pessoal.md) | Em que ponto do fluxo o dado pessoal deixa de existir |
| [0002](adr/0002-semantica-do-destino-do-streaming.md) | Que pergunta o índice de destino consegue responder |

O 0002 registra o ponto mais fácil de errar aqui: o índice é um **log de
eventos**, não um espelho do estado da origem. Um `delete` no Postgres vira mais
um documento no índice, não a remoção de um.

Índice geral em [`adr/`](../../adr/).
