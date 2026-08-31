"""A sequência do amazonsales, em Airflow.

Espelha a máquina de estado de
`../../scripts/step-functions-definitions/sfn_definition_s3tables_amazonsales.json`,
que é a forma AWS da mesma orquestração:

    stg_table
      -> dim_product | dim_rating | dim_user   (em paralelo)
      -> portão de qualidade das dimensões
      -> fact_product_rating | fact_sales_category   (em paralelo)
      -> portão de qualidade dos fatos

Os jobs são os MESMOS arquivos que rodam no Glue. O que muda é quem os dispara
e como: lá, `glue:startJobRun` pela máquina de estado; aqui, `spark-submit` no
contêiner do lakehouse.

O paralelismo e o encadeamento são idênticos de propósito — se o desenho da
sequência estiver errado, ele erra igual nos dois lugares, que é o que torna
este DAG útil como verificação.
"""

import os
from datetime import datetime

from airflow import DAG
from airflow.providers.standard.operators.bash import BashOperator

# O nome do contêiner do Spark vem do compose (parametros.env do workload),
# porque cada workload nomeia o seu. O default é o do serviço sem parâmetro.
CONTAINER = os.environ.get("GLUE_CONTAINER_NAME", "lakehouse-glue")
SCRIPTS = "/workspace/workloads/amazonsales/aws/scripts"

# Os mesmos argumentos que a máquina de estado passa a cada job. Estão aqui
# literalmente, e não montados por conveniência, para que divergir da forma AWS
# seja visível numa comparação lado a lado com o JSON.
#
# `s3_tables_bucket_arn` é exigido pela assinatura dos scripts mas ignorado
# localmente: o catálogo vem de ICEBERG_REST_URI.
ARN = "nao-usado-no-modo-local"
STG = "staged.stg_amazonsales"
DW = "datawarehouse"

JOBS = {
    "stg_table": (
        "dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py",
        f"--input_path s3a://sandbox-lake-raw-local/amazonsales/ "
        f"--iceberg_table stg_amazonsales --namespace staged "
        f"--primary_key product_id --s3_tables_bucket_arn {ARN}",
    ),
    "dim_product": (
        "dataeng-sandbox-amazonsales-dw-dim-product-s3tables.py",
        f"--stg_table_sales {STG} --output_table dim_product "
        f"--namespace_destino {DW} --s3_tables_bucket_arn {ARN}",
    ),
    "dim_rating": (
        "dataeng-sandbox-amazonsales-dw-dim-rating-s3tables.py",
        f"--stg_table_sales {STG} --output_table dim_rating "
        f"--namespace_destino {DW} --s3_tables_bucket_arn {ARN}",
    ),
    "dim_user": (
        "dataeng-sandbox-amazonsales-dw-dim-user-s3tables.py",
        f"--stg_table_sales {STG} --output_table dim_user "
        f"--namespace_destino {DW} --s3_tables_bucket_arn {ARN}",
    ),
    "portao_qualidade_dims": (
        "dataeng-sandbox-amazonsales-dw-dims-s3tables-gdq.py",
        f"--namespace {DW} --s3_tables_bucket_arn {ARN}",
    ),
    "fact_product_rating": (
        "dataeng-sandbox-amazonsales-dw-fact-product-rating-s3tables.py",
        f"--stg_table_sales {STG} --dim_product_table {DW}.dim_product "
        f"--dim_rating_table {DW}.dim_rating --output_table fact_product_rating "
        f"--namespace_destino {DW} --s3_tables_bucket_arn {ARN}",
    ),
    "fact_sales_category": (
        "dataeng-sandbox-amazonsales-dw-fact-sales-category-s3tables.py",
        f"--stg_table_sales {STG} --dim_product_table {DW}.dim_product "
        f"--dim_user_table {DW}.dim_user --output_table fact_sales_category "
        f"--namespace_destino {DW} --s3_tables_bucket_arn {ARN}",
    ),
    "portao_qualidade_fatos": (
        "dataeng-sandbox-amazonsales-dw-facts-s3tables-gdq.py",
        f"--namespace {DW} --s3_tables_bucket_arn {ARN}",
    ),
}


def job(nome_tarefa: str) -> BashOperator:
    """Dispara um job no contêiner do lakehouse.

    Falha do spark-submit falha a tarefa, e a tarefa falhada interrompe o resto
    do DAG — que é o mesmo contrato do `Catch` da máquina de estado.
    """
    script, argumentos = JOBS[nome_tarefa]
    return BashOperator(
        task_id=nome_tarefa,
        bash_command=f"docker exec {CONTAINER} spark-submit {SCRIPTS}/{script} {argumentos}",
    )


with DAG(
    dag_id="amazonsales",
    description="Star schema do amazonsales sobre Iceberg — forma local",
    start_date=datetime(2026, 1, 1),
    schedule=None,  # disparo manual: é laboratório, não produção
    catchup=False,
    tags=["amazonsales", "local"],
) as dag:
    stg = job("stg_table")

    dims = [
        job("dim_product"),
        job("dim_rating"),
        job("dim_user"),
    ]

    portao_dims = job("portao_qualidade_dims")

    fatos = [
        job("fact_product_rating"),
        job("fact_sales_category"),
    ]

    portao_fatos = job("portao_qualidade_fatos")

    stg >> dims >> portao_dims >> fatos >> portao_fatos
