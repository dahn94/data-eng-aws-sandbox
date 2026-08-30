# workloads/amazonsales/local

A forma local deste workload: a mesma sequência do Step Functions, em Airflow.

```
stg_table
  -> dim_product | dim_rating | dim_user        (em paralelo)
  -> portão de qualidade das dimensões
  -> fact_product_rating | fact_sales_category  (em paralelo)
  -> portão de qualidade dos fatos
```

É espelho de
[`../scripts/step-functions-definitions/sfn_definition_s3tables_amazonsales.json`](../scripts/step-functions-definitions/sfn_definition_s3tables_amazonsales.json).
Os jobs são **os mesmos arquivos** de `../scripts/`; o que muda é quem os
dispara: lá, `glue:startJobRun` pela máquina de estado; aqui, `spark-submit` no
contêiner do lakehouse.

O paralelismo e o encadeamento são idênticos de propósito. Se o desenho da
sequência estiver errado, ele erra igual nos dois lugares — é isso que torna o
DAG útil como verificação, e não apenas como conveniência.

## Rodar

```bash
# 1. o lakehouse, onde os jobs executam
docker compose -f ../../../platform/local/lakehouse/docker-compose.yml up -d

# 2. o orquestrador
docker compose -f ../../../platform/local/orchestration-airflow/docker-compose.yml up -d

# 3. dispare pela interface em http://localhost:8090, ou:
docker exec airflow airflow dags trigger amazonsales
```

## Estado

O DAG está registrado e sem erros de importação, e o cliente do Docker alcança
o contêiner do lakehouse a partir do Airflow — as duas coisas verificadas.

**A pipeline inteira ainda não foi executada de ponta a ponta**, porque falta o
dado de origem: nada publica os parquet que o `stg_table` lê. É a pendência do
[`../../DATASET.md`](../../DATASET.md), e enquanto ela existir o que está
verificado é a orquestração, não o resultado.
