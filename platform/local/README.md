# platform/local

A plataforma local, com a mesma forma da `../aws/`: um alicerce, uma rede, e as
peças reutilizáveis.

```
network/     rede.yml   a rede compartilhada — o análogo da VPC
foundation/             MinIO e os buckets — o análogo do S3 do foundation
services/               os motores, um por pasta
```

## Por que `services/` e não `modules/`

Na AWS, `modules/` guarda **modelos**: Terraform que um root module instancia. Um
`docker-compose.yml` não é modelo, é a coisa em si — quem o inclui não o
parametriza, apenas o sobe. Chamar de `modules` sugeriria uma indireção que não
existe.

`services/` é o nível dos *root modules* da AWS, não o dos módulos: cada pasta
sobe algo real e sozinho.

## A rede

`network/rede.yml` declara uma rede com `name` fixo — é isso que faz ela ser a
**mesma** entre projetos Compose diferentes. Sem o nome fixo, cada projeto
criaria a sua, com prefixo próprio, e os serviços não se enxergariam.

O arquivo não é um compose completo de propósito: um arquivo só com `networks`
não sobe nada (o Compose recusa com "no service selected"). Ele existe para ser
incluído, e a rede nasce junto do primeiro serviço que a use.

## Como se usa

Nada aqui é ponto de entrada. Quem compõe é o workload, em
`workloads/<nome>/local/infra/`, que inclui as peças de que precisa — do mesmo
jeito que `workloads/<nome>/aws/infra/` instancia os módulos de que precisa.

```bash
cd workloads/amazonsales/local/infra && docker compose up -d
```

> **Escolha um ponto de entrada e fique nele.** Subir uma peça direto daqui cria
> um projeto Compose diferente do que o workload cria. Os contêineres têm o
> mesmo nome, mas os **volumes levam o prefixo do projeto** — alternar deixa os
> dados anteriores órfãos, sem aviso.

## As peças

| Pasta | O que é | Análogo na AWS |
|---|---|---|
| `foundation/` | MinIO + os buckets, com os nomes que a AWS usa | S3 do `platform/aws/foundation` |
| `services/iceberg-catalog/` | catálogo Iceberg REST + Postgres | S3 Tables |
| `services/spark-glue/` | imagem oficial do Glue, com `awsglue` | Glue |
| `services/spark-oss/` | Apache Spark puro, sem fornecedor | — |
| `services/trino/` | o motor por trás do Athena | Athena |
| `services/streaming-cdc/` | Kafka + Debezium | DMS |
| `services/search-opensearch/` | OpenSearch + Dashboards | OpenSearch |
| `services/olap-clickhouse/` | ClickHouse | Redshift (só o mecanismo de MV) |
| `services/orchestration-airflow/` | Airflow | Step Functions |
| `services/bi-metabase/`, `bi-superset/` | BI | — |

Sem equivalente local: `DATASHARE` e zero-ETL do Redshift. São o produto, não uma
API — e por isso os workloads que dependem deles não têm forma local.
