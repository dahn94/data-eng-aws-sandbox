"""Funções compartilhadas pelos jobs Glue desta pipeline.

Este arquivo é enviado ao S3 pelo Terraform (módulo glue-job, variável
`shared_python_file`) e injetado nos jobs via `--extra-py-files`, então dá para
importá-lo normalmente:

    from glue_common import create_spark_session, write_table

Antes, cada um dos oito scripts carregava sua própria cópia de
`create_spark_session` e amigos — mudar a configuração do catálogo Iceberg
significava editar oito arquivos.
"""

import os
import sys

from awsglue.utils import getResolvedOptions
from pyspark.sql import DataFrame, SparkSession

# Nome do catálogo Spark que aponta para o bucket S3 Tables. Os nomes de tabela
# usados nos jobs são relativos a ele (é o defaultCatalog).
CATALOG = "s3tablesbucket"


def get_args(names):
    """Lê os argumentos nomeados do job (`--nome valor`)."""
    return getResolvedOptions(sys.argv, list(names))


def create_spark_session(s3_warehouse_arn, app_name="glue-s3-tables"):
    """Sessão Spark com o catálogo Iceberg configurado.

    O catálogo é Iceberg nos dois casos; muda a implementação e o endereço do
    warehouse — e é a ÚNICA diferença entre rodar na AWS e rodar local. Era uma
    constante fixa aqui dentro, o que tornava o script impossível de executar
    fora da AWS.

    Sem `ICEBERG_REST_URI` no ambiente, o comportamento é o de antes: S3 Tables,
    com o warehouse vindo do ARN passado pelo job. Com a variável definida
    (é o que `platform/local/lakehouse` faz), o mesmo script fala com o catálogo
    REST sobre o MinIO.
    """
    rest_uri = os.environ.get("ICEBERG_REST_URI", "")

    builder = (
        SparkSession.builder.appName(app_name)
        .config(
            "spark.sql.extensions",
            "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
        )
        .config("spark.sql.defaultCatalog", CATALOG)
        .config(f"spark.sql.catalog.{CATALOG}", "org.apache.iceberg.spark.SparkCatalog")
    )

    if rest_uri:
        s3_endpoint = os.environ.get("AWS_ENDPOINT_URL_S3", "")
        builder = (
            builder.config(f"spark.sql.catalog.{CATALOG}.catalog-impl",
                           "org.apache.iceberg.rest.RESTCatalog")
            .config(f"spark.sql.catalog.{CATALOG}.uri", rest_uri)
            .config(f"spark.sql.catalog.{CATALOG}.warehouse",
                    os.environ.get("ICEBERG_WAREHOUSE", "s3://sandbox-lakehouse/"))
            .config(f"spark.sql.catalog.{CATALOG}.io-impl",
                    "org.apache.iceberg.aws.s3.S3FileIO")
        )
        if s3_endpoint:
            # MinIO exige path-style: o DNS de bucket-por-subdomínio não existe.
            builder = (
                builder.config(f"spark.sql.catalog.{CATALOG}.s3.endpoint", s3_endpoint)
                .config(f"spark.sql.catalog.{CATALOG}.s3.path-style-access", "true")
            )
    else:
        builder = (
            builder.config(f"spark.sql.catalog.{CATALOG}.catalog-impl",
                           "software.amazon.s3tables.iceberg.S3TablesCatalog")
            .config(f"spark.sql.catalog.{CATALOG}.warehouse", s3_warehouse_arn)
        )

    return builder.getOrCreate()


def read_table(spark: SparkSession, table: str) -> DataFrame:
    """Lê uma tabela do catálogo, no formato `namespace.tabela`."""
    return spark.sql(f"SELECT * FROM {table}")


def ensure_namespace(spark: SparkSession, namespace: str) -> None:
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {CATALOG}.{namespace}")


def ensure_table(spark: SparkSession, namespace: str, table: str, schema) -> None:
    """Cria a tabela se ela não existir, a partir de uma lista (coluna, tipo).

    Aceita tanto `df.dtypes` quanto uma lista escrita à mão.
    """
    ddl = ", ".join(f"{name} {dtype}" for name, dtype in schema)
    spark.sql(f"CREATE TABLE IF NOT EXISTS {namespace}.{table} ({ddl})")


def assert_schema_matches(spark: SparkSession, namespace: str, table: str, df: DataFrame) -> None:
    """Falha cedo se o DataFrame não casar com a tabela que já existe.

    `CREATE TABLE IF NOT EXISTS` silenciosamente não faz nada quando a tabela
    existe com outro formato — e o INSERT seguinte falha com um erro de Spark
    difícil de ler. Melhor dizer exatamente qual coluna divergiu.
    """
    existing = [f.name for f in spark.table(f"{namespace}.{table}").schema.fields]
    incoming = [f.name for f in df.schema.fields]
    if existing != incoming:
        raise ValueError(
            f"Schema divergente em {namespace}.{table}.\n"
            f"  tabela existente: {existing}\n"
            f"  dados de entrada: {incoming}\n"
            "Apague a tabela ou ajuste o job antes de continuar."
        )


def write_table(spark: SparkSession, df: DataFrame, namespace: str, table: str) -> None:
    """Sobrescreve a tabela inteira com o conteúdo do DataFrame.

    É um full refresh de propósito: os volumes deste sandbox são pequenos e o
    resultado é sempre reproduzível. Para carga incremental, use `merge_table`.
    """
    ensure_namespace(spark, namespace)
    ensure_table(spark, namespace, table, df.dtypes)
    assert_schema_matches(spark, namespace, table, df)

    view = f"_write_{table}"
    df.createOrReplaceTempView(view)
    spark.sql(f"INSERT OVERWRITE {namespace}.{table} SELECT * FROM {view}")


def merge_table(
    spark: SparkSession, df: DataFrame, namespace: str, table: str, primary_key: str
) -> None:
    """Upsert por chave primária (uma ou mais colunas separadas por vírgula)."""
    ensure_namespace(spark, namespace)
    ensure_table(spark, namespace, table, df.dtypes)
    assert_schema_matches(spark, namespace, table, df)

    view = f"_merge_{table}"
    df.createOrReplaceTempView(view)

    pk_cols = [c.strip() for c in primary_key.split(",")]
    on_clause = " AND ".join(f"target.{c} = source.{c}" for c in pk_cols)
    set_clause = ", ".join(f"{c} = source.{c}" for c in df.columns)

    spark.sql(
        f"""
        MERGE INTO {namespace}.{table} AS target
        USING {view} AS source
        ON {on_clause}
        WHEN MATCHED THEN UPDATE SET {set_clause}
        WHEN NOT MATCHED THEN INSERT *
        """
    )


# ---------------------------------------------------------------------------
# Data Quality
# ---------------------------------------------------------------------------
def evaluate_data_quality(df, glue_context, context_name, ruleset, results_s3_prefix=None):
    """Avalia um ruleset do Glue Data Quality e devolve (passou, linhas).

    Os imports ficam aqui dentro porque `awsgluedq` só existe no runtime do
    Glue — importá-lo no topo quebraria os jobs que não fazem DQ.
    """
    from awsglue.dynamicframe import DynamicFrame
    from awsglue.transforms import SelectFromCollection
    from awsgluedq.transforms import EvaluateDataQuality

    publishing_options = {
        "dataQualityEvaluationContext": context_name,
        "enableDataQualityCloudWatchMetrics": True,
        "enableDataQualityResultsPublishing": True,
    }
    if results_s3_prefix:
        publishing_options["resultsS3Prefix"] = results_s3_prefix

    evaluated = EvaluateDataQuality().process_rows(
        frame=DynamicFrame.fromDF(df, glue_context, context_name),
        ruleset=ruleset,
        publishing_options=publishing_options,
        additional_options={"performanceTuning.caching": "CACHE_NOTHING"},
    )

    outcomes = SelectFromCollection.apply(
        dfc=evaluated, key="ruleOutcomes", transformation_ctx="ruleOutcomes"
    ).toDF()

    rows = outcomes.collect()
    failures = [r for r in rows if r["Outcome"] != "Passed"]
    return failures, rows


def run_data_quality_gate(tables, glue_context, rulesets, context_prefix, results_s3_prefix=None):
    """Roda o DQ em várias tabelas e **falha o job** se alguma regra falhar.

    Sem este `raise`, o job terminava com sucesso mesmo com regra reprovada: o
    Step Functions seguia adiante e a pipeline ficava verde com dado ruim.
    Falhando aqui, o `Catch` da máquina de estado interrompe o resto.
    """
    all_failures = {}

    for table_name, df in tables.items():
        print(f"Avaliando qualidade de: {table_name}")
        failures, rows = evaluate_data_quality(
            df,
            glue_context,
            f"{context_prefix}_{table_name}",
            rulesets[table_name],
            results_s3_prefix,
        )

        for row in rows:
            print(f"  [{row['Outcome']}] {row['Rule']}")

        if failures:
            all_failures[table_name] = [r["Rule"] for r in failures]

    if all_failures:
        detail = "\n".join(
            f"  {table}: {', '.join(rules)}" for table, rules in all_failures.items()
        )
        raise ValueError(f"Regras de qualidade reprovadas:\n{detail}")

    print("Todas as regras de qualidade passaram.")
