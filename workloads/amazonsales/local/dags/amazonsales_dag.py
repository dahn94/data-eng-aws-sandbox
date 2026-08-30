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

from datetime import datetime

from airflow import DAG
from airflow.providers.standard.operators.bash import BashOperator

CONTAINER = "lakehouse-glue"
SCRIPTS = "/workspace/workloads/amazonsales/scripts"
NAMESPACE = "lakehouse"

# O `arn` só é usado no caminho AWS; local, o catálogo vem de ICEBERG_REST_URI.
ARGS_COMUNS = f"--namespace {NAMESPACE} --s3_tables_bucket_arn nao-usado-local"


def job(nome_tarefa: str, script: str) -> BashOperator:
    """Dispara um job no contêiner do lakehouse.

    Falha do spark-submit falha a tarefa, e a tarefa falhada interrompe o resto
    do DAG — que é o mesmo contrato do `Catch` da máquina de estado.
    """
    return BashOperator(
        task_id=nome_tarefa,
        bash_command=(
            f"docker exec {CONTAINER} spark-submit "
            f"{SCRIPTS}/{script} {ARGS_COMUNS}"
        ),
    )


with DAG(
    dag_id="amazonsales",
    description="Star schema do amazonsales sobre Iceberg — forma local",
    start_date=datetime(2026, 1, 1),
    schedule=None,  # disparo manual: é laboratório, não produção
    catchup=False,
    tags=["amazonsales", "local"],
) as dag:
    stg = job("stg_table", "dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py")

    dims = [
        job("dim_product", "dataeng-sandbox-amazonsales-dw-dim-product-s3tables.py"),
        job("dim_rating", "dataeng-sandbox-amazonsales-dw-dim-rating-s3tables.py"),
        job("dim_user", "dataeng-sandbox-amazonsales-dw-dim-user-s3tables.py"),
    ]

    portao_dims = job(
        "portao_qualidade_dims", "dataeng-sandbox-amazonsales-dw-dims-s3tables-gdq.py"
    )

    fatos = [
        job("fact_product_rating", "dataeng-sandbox-amazonsales-dw-fact-product-rating-s3tables.py"),
        job("fact_sales_category", "dataeng-sandbox-amazonsales-dw-fact-sales-category-s3tables.py"),
    ]

    portao_fatos = job(
        "portao_qualidade_fatos", "dataeng-sandbox-amazonsales-dw-facts-s3tables-gdq.py"
    )

    stg >> dims >> portao_dims >> fatos >> portao_fatos
