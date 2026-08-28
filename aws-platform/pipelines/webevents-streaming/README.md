# aws-platform/pipelines/webevents-streaming

Job Glue de **streaming** que lê o CDC de `web_events` do Kafka (formato Avro
do Debezium), limpa os dados e grava no OpenSearch em tempo real.

## Pré-requisitos

1. **`aws-platform/foundation` aplicado** — buckets de scripts e de logs.
2. **Os jars baixados** — `./scripts/fetch-jars.sh` na raiz. São 5 jars
   (Kafka, Avro, OpenSearch para Spark) que o Terraform envia ao S3.
3. **Kafka, Schema Registry e OpenSearch alcançáveis** a partir da AWS.
   Normalmente uma instância EC2 rodando `local-services/streaming-cdc` e
   `local-services/search-opensearch`. O endereço vai em `streaming_host`.
4. **O connector Debezium registrado**, publicando no tópico
   `ecommerce.public.web_events` — veja `local-services/streaming-cdc`.

## Aplicar

```bash
cd aws-platform/pipelines/webevents-streaming
terraform init -backend-config=backends/develop.hcl
export TF_VAR_opensearch_password='a-senha-do-admin-do-opensearch'
terraform apply -var-file=envs/develop.tfvars \
  -var="streaming_host=<ip-publico-da-ec2>"
```

Substitua também o `streaming_host = "CHANGEME.exemplo.invalid"` em
`envs/*.tfvars` se preferir fixá-lo.

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
