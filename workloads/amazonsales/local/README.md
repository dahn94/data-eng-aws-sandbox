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

### Disparo pelo Airflow

```bash
docker exec airflow airflow dags trigger amazonsales
```

**Verificado:** as oito tarefas em `success`, com as três dimensões rodando em
paralelo — o mesmo paralelismo da máquina de estado.

Três coisas precisaram ser resolvidas para chegar aqui, e as três só apareceram
executando:

1. **Duas chamadas multi-linha no DAG passavam dois argumentos** para uma função
   de um. `py_compile` não pega isso: é sintaxe válida. O sintoma era o run
   preso em `queued` para sempre, sem erro visível — o scheduler não despacha um
   DAG cuja versão atual falha ao ser lida.
2. **O catálogo Iceberg não aguentava escrita concorrente.** O
   `apache/iceberg-rest-fixture` usa um JDBC em memória; com as três dimensões
   em paralelo ele devolvia `Failed to get table ... from catalog rest_backend`.
   Resolvido dando um Postgres ao catálogo, em vez de serializar o DAG — o
   paralelismo é do desenho, e serializar esconderia o problema em vez de
   resolvê-lo.
3. **`great_expectations` não estava na imagem.** Instalar à mão no contêiner
   dura até o primeiro `docker compose down`. Agora está no Dockerfile, na mesma
   versão que o `additional_python_modules` do `main.tf` declara para a AWS.
