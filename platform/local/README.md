# platform/local

A plataforma local, com a mesma forma da `../aws/`: um alicerce, uma rede e as
peças que os workloads consomem.

**Ela está em transição.** Há dois caminhos aqui, e os dois funcionam:

```
modules/                os charts: um motor por pasta, INSTANCIÁVEL      ← o destino
cluster/     kind.yaml  o cluster local — o análogo da VPC
adr/                    por que a transição existe

services/               os mesmos motores em docker-compose.yml          ← a origem
network/     rede.yml   a rede compartilhada do Compose
foundation/             MinIO e os buckets, na forma Compose
```

O Compose só sai quando o caminho equivalente estiver verificado no cluster —
não se troca um ambiente que funciona por um que ainda não foi exercitado. Os
Dockerfiles seguem em `services/`, e os dois caminhos constroem **a mesma
imagem**; quando o Compose sair, eles vão junto para `modules/`.

## Por que `modules/` e não `services/`

Na AWS, `modules/` guarda **modelos**: Terraform que não sobe nada sozinho e só
existe instanciado. Um `docker-compose.yml` não é isso — ele sobe sozinho, e
**não é instanciável**: incluir o mesmo arquivo duas vezes no mesmo projeto,
com parâmetros diferentes, não dá dois serviços, dá um só com os parâmetros
embaralhados, em silêncio. Por isso `services/` era o nome honesto para ele.

Um chart é instanciável: `helm install a` e `helm install b`, em namespaces
diferentes, dão duas instalações independentes, cada uma com o seu Service, o
seu PVC e o seu DNS. É a mesma relação que `workloads/*/aws/infra` tem com
`platform/aws/modules` — e é o que faz os dois lados do repositório passarem a
ter modelo e instanciação com o mesmo significado.

O porquê disso importar está no
[ADR 0001](adr/0001-isolar-o-dado-que-cada-workload-mede.md): não é estética de
nomenclatura, é que hoje dois workloads locais escrevem no mesmo MinIO e no
mesmo catálogo, então um pode alterar o número que o outro mediu.

## Como se usa o caminho novo

```bash
./scripts/k8s-up.sh        # cria o cluster (kind) e fixa o contexto
./scripts/k8s-images.sh    # constrói o que falta e carrega no cluster

cd workloads/amazonsales/local/infra
helm dependency build      # resolve os modelos de platform/local/modules
helm install amazonsales . -n amazonsales --create-namespace
```

> **`helm dependency build` tira uma fotografia.** Os modelos entram em
> `charts/*.tgz` no momento em que você roda o comando; editar um chart de
> `modules/` depois disso **não** muda o que o `helm upgrade` instala. Rode o
> `dependency build` de novo — foi assim que uma variável editada não chegou no
> cluster durante esta migração.

Detalhes do cluster, do acesso às interfaces e do limite de RAM em
[`cluster/README.md`](cluster/README.md).

## O caminho do Compose

O que está descrito daqui até o fim vale para `services/`, que continua sendo o
caminho verificado enquanto a transição não termina.

## Os parâmetros

Todo campo que um workload pode querer diferente é uma variável com o valor de
hoje como default: nome de contêiner, porta de host, versão da imagem,
credencial. **O prefixo é o do serviço** (`TRINO_`, `CLICKHOUSE_`,
`ICEBERG_REST_`…), porque tudo desemboca num arquivo só por workload.

| Serviço | Variáveis |
|---|---|
| `foundation/` | `MINIO_VERSION`, `MINIO_MC_VERSION`, `MINIO_CONTAINER_NAME`, `MINIO_SETUP_CONTAINER_NAME`, `MINIO_API_PORT`, `MINIO_CONSOLE_PORT`, `MINIO_BUCKETS` |
| `iceberg-catalog/` | `ICEBERG_REST_VERSION`, `ICEBERG_REST_CONTAINER_NAME`, `ICEBERG_REST_PORT`, `ICEBERG_WAREHOUSE_BUCKET`, `ICEBERG_CATALOG_DB_*` (`VERSION`, `CONTAINER_NAME`, `USER`, `PASSWORD`, `NAME`) |
| `spark-glue/` | `GLUE_VERSION`, `GLUE_CONTAINER_NAME` |
| `spark-oss/` | `SPARK_OSS_VERSION`, `SPARK_OSS_CONTAINER_NAME` |
| `trino/` | `TRINO_VERSION`, `TRINO_CONTAINER_NAME`, `TRINO_PORT` |
| `olap-clickhouse/` | `CLICKHOUSE_VERSION`, `CLICKHOUSE_CONTAINER_NAME`, `CLICKHOUSE_HTTP_PORT`, `CLICKHOUSE_NATIVE_PORT`, `CLICKHOUSE_DB`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD` |
| `orchestration-airflow/` | `AIRFLOW_VERSION`, `AIRFLOW_CONTAINER_NAME`, `AIRFLOW_PORT`, `AIRFLOW_DAGS_PATH`, `AIRFLOW_DAGS_NAME`, `GLUE_CONTAINER_NAME` |
| `search-opensearch/` | `OPENSEARCH_VERSION`, `OPENSEARCH_HEAP`, `OPENSEARCH_HTTP_PORT`, `OPENSEARCH_PERF_PORT`, `OPENSEARCH_DASHBOARDS_PORT`, `OPENSEARCH_*_CONTAINER_NAME` |
| `streaming-cdc/` | `DEBEZIUM_VERSION`, `EC2_IP`, `KAFKA_*`, `ZOOKEEPER_*`, `SCHEMA_REGISTRY_*`, `CONNECT_*`, `KAFKA_UI_*` (`CONTAINER_NAME`, `PORT`) |
| `bi-metabase/` | `METABASE_VERSION`, `METABASE_CONTAINER_NAME`, `METABASE_PORT`, `METABASE_DB_*` |
| `bi-superset/` | `SUPERSET_CONTAINER_NAME`, `SUPERSET_PORT`, `SUPERSET_SECRET_KEY`, `SUPERSET_DB_*` |

### Quem sobrescreve quem

Medido, e é o **contrário** do que a intuição diz — o `env_file:` do `include`
é a camada mais fraca, não um override:

```
default no ${VAR:-...}  <  env_file: do include  <  .env do diretório  <  shell
```

Cada camada tem o papel que a precedência dela permite:

| Camada | Para quê | Versionado? |
|---|---|---|
| `${VAR:-valor}` no serviço | o que acontece se ninguém disser nada | sim |
| `parametros.env` do workload, pelo `env_file:` do `include` | a identidade do workload — nomes, portas, o DAG que o Airflow monta | **sim** — é o que faz o nome ser o mesmo em qualquer clone |
| `.env` no diretório do workload | o ajuste da SUA máquina (porta ocupada, credencial) | não (gitignored) |
| variável exportada no shell | o teste de uma vez só | — |

Uma consequência prática: um `env_file:` do `include` **não** pode apontar para
um arquivo gitignored, e um arquivo inexistente ali é erro fatal, não aviso.

## Nomes de contêiner

O nome de contêiner é global na máquina, não do projeto Compose: dois projetos
que subam a mesma peça com o mesmo `container_name` **roubam o contêiner um do
outro**, sem aviso. Por isso cada workload nomeia as suas peças em
`parametros.env` — `amazonsales-minio` e não `lakehouse-minio` — e o `docker ps`
passa a dizer de quem é cada uma.

Isso não muda como os serviços se acham: dentro da rede `dados` o endereço
continua sendo o **nome do serviço** (`minio`, `trino`, `clickhouse`), que o
Compose registra como alias independente do `container_name`.

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
> um projeto Compose diferente do que o workload cria, e os **volumes levam o
> prefixo do projeto** — alternar deixa os dados anteriores órfãos, sem aviso.
> Os contêineres também mudam de nome, porque daqui valem os defaults e não o
> `parametros.env` do workload.

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
