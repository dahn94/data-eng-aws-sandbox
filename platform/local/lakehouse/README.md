# platform/local/lakehouse

O lakehouse local: **S3, catálogo e Spark de verdade**, em contêiner. É o que
substituiu o LocalStack.

A diferença não é de ferramenta, é de propósito. O emulador criava recursos da
AWS e nunca executava a lógica — o README dele admitia que *"criar um job Glue
≠ executar um job Glue"*. Aqui não existe recurso nenhum da AWS, e a lógica
roda de verdade: o mesmo PySpark, lendo e escrevendo Iceberg sobre um S3 real,
com um catálogo real.

O raciocínio completo está em
[`adr/0001`](../../../adr/0001-rodar-local-sem-emular-a-nuvem.md).

## O mapeamento

| Na AWS | Aqui | O que muda |
|---|---|---|
| S3 | **MinIO** | nada de relevante: mesma API, mesmos nomes de bucket |
| S3 Tables | **catálogo Iceberg REST** | mesma especificação de tabela, sem o gerenciamento |
| Glue (Spark) | **`public.ecr.aws/glue/aws-glue-libs:5.0.10`** | imagem oficial da AWS, mesmo Spark e mesmas libs do Glue 5.0 |

Os buckets nascem com **os mesmos nomes** que o `platform/aws/foundation` cria na
AWS, com prefixo `sandbox` e ambiente `local`:

```
sandbox-lake-configs          scripts e jars
sandbox-lake-raw-local        dado bruto
sandbox-lake-curated-local    dado curado
sandbox-lake-logs-local       checkpoints do Spark
sandbox-lakehouse             warehouse do catálogo Iceberg (o análogo do S3 Tables)
```

Isso é deliberado: se os nomes divergissem, o script que roda aqui deixaria de
ser o script que roda lá.

## Subir

```bash
cp .env.example .env
docker compose up -d
```

| Serviço | Onde responde |
|---|---|
| MinIO — API S3 | `http://localhost:9000` |
| MinIO — console | `http://localhost:9001` (`minioadmin` / `minioadmin`) |
| Catálogo Iceberg REST | `http://localhost:8181` |

O contêiner do Glue fica de pé sem fazer nada, para você entrar nele:

```bash
docker compose exec glue bash
```

O repositório inteiro está montado em `/workspace`, somente leitura.

> **A imagem do Glue tem vários GB.** O primeiro `up` demora bastante, e é só
> na primeira vez.

## O que este ambiente **não** cobre

Ser explícito aqui vale mais que a matriz de cobertura, porque é o que evita
concluir que algo "está validado".

- **Redshift não tem equivalente.** O `incremental-mv`, o `zero-etl` e o
  `data-sharing` não rodam aqui, e nem tentam: eles não têm ambiente local. O
  `platform/local/olap-clickhouse` ensina o *mecanismo* de materialized view
  mantida pelo motor, mas `DATASHARE` e zero-ETL só existem na AWS.
- **Debezium não é DMS.** São implementações diferentes de CDC. A semântica que
  o `workloads/dms/adr/0001` discute precisa da AWS para ser medida.
- **Não há Athena.** O `federated-query` roda em Athena, que é Trino
  gerenciado; Trino local é fiel como motor, mas não reproduz o modelo de
  cobrança por bytes escaneados. Está previsto para depois.
- **Não há IAM.** Nada aqui testa permissão. Um script que funciona local pode
  falhar na AWS por falta de política — e isso é `terraform plan` e `apply`,
  não este ambiente.

## Estado: verificado em execução

Este ambiente foi executado de verdade em 2026-08-29, em `aarch64`, e o
resultado está registrado abaixo porque muda o que dá para afirmar.

**Funciona:** os cinco buckets nascem, o catálogo REST responde, e o
`glue_common.py` do `amazonsales` cria namespace, cria tabela, escreve e lê uma
tabela Iceberg — com os parquet e os snapshots aparecendo no MinIO. O
`INSERT OVERWRITE` foi conferido de fato substituindo, e não somando: reescrever
com uma linha devolve uma linha.

**Não funciona:** `awsgluedq` **não existe na imagem oficial da AWS**. Só as
libs `awsglue` estão lá. Como o portão de qualidade do `amazonsales` depende de
`awsgluedq.transforms.EvaluateDataQuality`, os jobs que passam por ele não rodam
aqui — e o `workloads/amazonsales/adr/0005` continua sem verificação local.

**Pegadinha da imagem:** ela traz `spark.sql.catalogImplementation hive`, e nem
todo comando SQL resolve pelo `defaultCatalog`. `CREATE TABLE ns.tbl` ia para o
catálogo Iceberg, mas `INSERT OVERWRITE ns.tbl` caía no Hive e tentava falar com
o Glue Data Catalog, falhando com `StsException`. Por isso todas as referências
a tabela em `glue_common.py` passaram a ser qualificadas com o catálogo.
