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

**A pipeline roda de ponta a ponta**, com dado semeado por
[`../seed/`](../seed/). Verificado disparando os oito jobs em sequência no
contêiner do lakehouse:

| tabela | linhas |
|---|---|
| `staged.stg_amazonsales` | 50 (de 101 na origem — o dedup descartou 51) |
| `datawarehouse.dim_product` | 50 |
| `datawarehouse.dim_rating` | 50 |
| `datawarehouse.dim_user` | 23 |
| `datawarehouse.fact_product_rating` | 50 |
| `datawarehouse.fact_sales_category` | 44 |

Os dois portões de qualidade passaram, e o star schema foi consultado pelo
Trino — outro motor, mesmo catálogo.

Para reproduzir, do zero:

```bash
# 1. semear a origem
docker exec lakehouse-glue spark-submit \
  /workspace/workloads/amazonsales/seed/gerar_dataset.py \
  --saida s3a://sandbox-lake-raw-local/amazonsales/ --produtos 50 --semente 42

# 2. os oito jobs, na ordem do DAG — os argumentos estão em dags/amazonsales_dag.py
docker exec lakehouse-glue spark-submit \
  /workspace/workloads/amazonsales/scripts/dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py \
  --input_path s3a://sandbox-lake-raw-local/amazonsales/ --iceberg_table stg_amazonsales \
  --namespace staged --primary_key product_id --s3_tables_bucket_arn nao-usado-no-modo-local
# ... e assim por diante
```

### O que NÃO funciona: o disparo pelo Airflow

O DAG é lido sem erro, as oito tarefas aparecem, e o cliente do Docker alcança
o `lakehouse-glue` de dentro do Airflow. Mas **um `dags trigger` fica preso em
`queued`**: as instâncias de tarefa são criadas com estado nulo e o scheduler
nunca as despacha, mesmo com o `LocalExecutor` carregado e sem erro no log.

O que já foi descartado: DAG com erro de importação, DAG pausado, executor não
carregado, e o override de `AIRFLOW__CORE__EXECUTOR` que eu tinha posto.

Suspeita não confirmada: o modo `standalone` do Airflow 3 com o volume nomeado
montado sobre `/opt/airflow`, ou a URL do servidor de execução que o Task SDK
usa. **Enquanto isso não for resolvido, a orquestração é declarativa: o DAG
descreve a sequência certa, mas quem a executa hoje é o `spark-submit` direto.**
