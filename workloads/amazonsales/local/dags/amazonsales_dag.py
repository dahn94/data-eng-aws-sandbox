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
e como: lá, `glue:startJobRun` pela máquina de estado; aqui, `spark-submit` —
num contêiner, quando a plataforma local é Compose, ou num pod por tarefa,
quando é Kubernetes. `MODO_EXECUCAO` decide, e nenhum job muda.

O paralelismo e o encadeamento são idênticos de propósito — se o desenho da
sequência estiver errado, ele erra igual nos dois lugares, que é o que torna
este DAG útil como verificação.
"""

import os
from datetime import datetime

from airflow import DAG

# Qual plataforma local está por baixo. `docker` mantém o caminho do Compose
# funcionando sem nada configurado; o chart do Airflow põe `kubernetes`.
MODO_EXECUCAO = os.environ.get("MODO_EXECUCAO", "docker")

# Compose: o nome do contêiner do Spark vem do parametros.env do workload,
# porque cada workload nomeia o seu.
CONTAINER = os.environ.get("GLUE_CONTAINER_NAME", "lakehouse-glue")

# Kubernetes: o namespace, a imagem e o repositório montado chegam do chart —
# o DAG não adivinha em que namespace está.
NAMESPACE = os.environ.get("JOBS_NAMESPACE", "default")
IMAGEM = os.environ.get("JOBS_IMAGE", "dataeng-sandbox/glue:5.0.10-gx")
REPO_NO_NO = os.environ.get("JOBS_REPO_HOST_PATH", "/repo")
REPO_NO_POD = os.environ.get("JOBS_REPO_MOUNT_PATH", "/workspace")

SCRIPTS = f"{REPO_NO_POD}/workloads/amazonsales/aws/scripts"

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


# As variáveis que o job precisa para achar o storage e o catálogo. No Compose
# elas já estão no contêiner do Spark; no Kubernetes o pod nasce a cada tarefa,
# então viajam com ele.
AMBIENTE_DO_JOB = {
    chave: os.environ[chave]
    for chave in (
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_REGION",
        "AWS_ENDPOINT_URL_S3",
        "ICEBERG_REST_URI",
    )
    if chave in os.environ
}


# Declarados para que o escalonador saiba o que reservar: sem isto o pod entra
# como "best effort" e concorre com os motores que já estão de pé.
def _recursos():
    from kubernetes.client import models as k8s

    return k8s.V1ResourceRequirements(
        requests={"cpu": "500m", "memory": "2Gi"}, limits={"memory": "6Gi"}
    )


def job(nome_tarefa: str):
    """Dispara um job do lakehouse.

    Falha do spark-submit falha a tarefa, e a tarefa falhada interrompe o resto
    do DAG — que é o mesmo contrato do `Catch` da máquina de estado, nos dois
    modos.
    """
    script, argumentos = JOBS[nome_tarefa]
    comando = f"spark-submit {SCRIPTS}/{script} {argumentos}"

    if MODO_EXECUCAO == "kubernetes":
        # Importado aqui dentro de propósito: no caminho do Compose o provider
        # de Kubernetes não está instalado, e um import no topo quebraria o
        # arquivo inteiro em vez de só o que não se usa.
        from airflow.providers.cncf.kubernetes.operators.pod import (
            KubernetesPodOperator,
        )
        from kubernetes.client import models as k8s

        RECURSOS_DO_JOB = _recursos()

        return KubernetesPodOperator(
            task_id=nome_tarefa,
            name=f"amazonsales-{nome_tarefa}".replace("_", "-"),
            namespace=NAMESPACE,
            image=IMAGEM,
            # A imagem foi construída nesta máquina e carregada no cluster por
            # scripts/k8s-images.sh: buscar no registry remoto só daria
            # ErrImagePull.
            image_pull_policy="IfNotPresent",
            # O ENTRYPOINT da imagem do Glue é `bash -l`; o comando entra como
            # argumento dele.
            cmds=["bash", "-lc"],
            arguments=[comando],
            env_vars=AMBIENTE_DO_JOB,
            volumes=[
                k8s.V1Volume(
                    name="repo",
                    host_path=k8s.V1HostPathVolumeSource(
                        path=REPO_NO_NO, type="Directory"
                    ),
                )
            ],
            volume_mounts=[
                k8s.V1VolumeMount(
                    name="repo", mount_path=REPO_NO_POD, read_only=True
                )
            ],
            get_logs=True,
            on_finish_action="delete_pod",
            # O default de 120s é curto para uma máquina de estudo, onde o nó
            # cria vários pods ao mesmo tempo. (Não confundir com o 403 de
            # `events` que já derrubou tarefas aqui: aquilo era RBAC, e está
            # resolvido no chart do Airflow.)
            startup_timeout_seconds=300,
            log_events_on_failure=True,
            container_resources=RECURSOS_DO_JOB,
        )

    from airflow.providers.standard.operators.bash import BashOperator

    return BashOperator(
        task_id=nome_tarefa,
        bash_command=f"docker exec {CONTAINER} {comando}",
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
