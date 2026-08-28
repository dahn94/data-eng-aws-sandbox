# aws-platform/pipelines/amazonsales

Pipeline batch: transforma os dados brutos de vendas (Amazon Sales) em
dimensões e fatos no formato Iceberg (S3 Tables), com jobs de Data Quality e um
Step Function que orquestra a execução.

## Pré-requisitos

Esta pipeline não depende do state de outro root module, mas depende de coisas
que precisam existir:

1. **`aws-platform/foundation` aplicado** — cria o bucket de scripts, o de
   dados curados e o bucket S3 Tables (`dataeng-sandbox-lakehouse-<amb>`).
2. **Os jars baixados** — `./scripts/fetch-jars.sh` na raiz do repositório.
   O Terraform envia o jar do catálogo Iceberg para o S3; sem o arquivo local,
   o `plan` falha dizendo qual arquivo falta.
3. **Dados em `s3://<prefixo>-lake-raw-<amb>/raw/postgres/public/amazon/`** —
   é de onde o job de staging lê. Normalmente vêm do `aws-platform/dms`
   replicando uma tabela `amazon` do Postgres. O caminho é configurável em
   `raw_input_prefix` e precisa casar com `raw_output_prefix` do DMS.

## Aplicar

```bash
cd aws-platform/pipelines/amazonsales
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars
```

Executar a pipeline:

```bash
aws stepfunctions start-execution \
  --state-machine-arn "$(terraform output -json state_machine_arns | jq -r '.[]')"
```

## Conteúdo

- `scripts/glue_common.py` — funções compartilhadas pelos 8 jobs (sessão Spark
  com o catálogo Iceberg, criação de namespace, escrita, merge, portão de Data
  Quality). Enviado ao S3 e injetado via `--extra-py-files`; mudar a
  configuração do catálogo é editar **um** arquivo, não oito.
- `scripts/*.py` — os jobs: staging, três dimensões, dois fatos, dois de DQ.
- `scripts/step-functions-definitions/` — a definição JSON, um template.
  Os `${...}` (conta, região, ambiente, ARN do lakehouse, caminho de entrada)
  são preenchidos pelo Terraform, então o JSON não carrega nome de bucket nem
  ID de conta.
- `jars/` — o jar do catálogo S3 Tables, baixado por `scripts/fetch-jars.sh`
  e enviado ao S3 pelo Terraform. Não versionado.

## O fluxo

```
stg_table → [dim_product | dim_rating | dim_user] → dims_data_quality
          → [fact_product_rating | fact_sales_category] → facts_data_quality
```

## Data Quality

Os jobs `*-gdq` avaliam rulesets do Glue Data Quality e **falham** quando uma
regra reprova. Como o Step Function tem um `Catch` em cada estado, a execução
para: se a qualidade das dimensões falhar, os fatos não são construídos.

Limitação honesta: o DQ roda **depois** da escrita, não antes. As dimensões já
estão gravadas quando o portão reprova — o que ele impede é a propagação para
os fatos. Um write-audit-publish de verdade exigiria namespaces de staging
separados e um passo de promoção; é um bom próximo exercício.

Os resultados são publicados em
`s3://<prefixo>-lake-curated-<amb>/data_quality_results/<amb>/` e como métricas
no CloudWatch.

## Adicionando um job novo

1. Coloque o script em `scripts/`, importando o que precisar de `glue_common`.
2. Adicione uma entrada no mapa `job_scripts` em `main.tf`.
3. Se ele precisar entrar na orquestração, adicione um `State` na definição
   JSON. Use `${...}` para qualquer valor específico de conta ou ambiente e
   declare-o em `template_variables`.

## Custo

Glue cobra por execução (~US$0,44 por DPU-hora), com mínimo de 1 minuto. Uma
execução completa desta pipeline com dados de estudo custa centavos. Nada fica
cobrando parado.
