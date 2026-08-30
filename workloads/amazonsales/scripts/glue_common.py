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

# Nome do catálogo Spark do lakehouse. TODA referência a tabela neste arquivo é
# qualificada com ele — `{CATALOG}.{namespace}.{table}` — e não apenas
# `{namespace}.{table}`.
#
# Não é preciosismo: a imagem do Glue traz `spark.sql.catalogImplementation
# hive`, e nem todo comando SQL resolve pelo `defaultCatalog`. Medido rodando:
# `CREATE TABLE ns.tbl` resolvia para o catálogo Iceberg, mas
# `INSERT OVERWRITE ns.tbl` caía no Hive e tentava falar com o Glue Data
# Catalog — falhando com StsException. Qualificar remove a ambiguidade nos dois
# ambientes; na AWS o resultado é idêntico ao de antes.
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
    return spark.sql(f"SELECT * FROM {CATALOG}.{table}")


def ensure_namespace(spark: SparkSession, namespace: str) -> None:
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {CATALOG}.{namespace}")


def ensure_table(spark: SparkSession, namespace: str, table: str, schema) -> None:
    """Cria a tabela se ela não existir, a partir de uma lista (coluna, tipo).

    Aceita tanto `df.dtypes` quanto uma lista escrita à mão.
    """
    ddl = ", ".join(f"{name} {dtype}" for name, dtype in schema)
    spark.sql(f"CREATE TABLE IF NOT EXISTS {CATALOG}.{namespace}.{table} ({ddl})")


def assert_schema_matches(spark: SparkSession, namespace: str, table: str, df: DataFrame) -> None:
    """Falha cedo se o DataFrame não casar com a tabela que já existe.

    `CREATE TABLE IF NOT EXISTS` silenciosamente não faz nada quando a tabela
    existe com outro formato — e o INSERT seguinte falha com um erro de Spark
    difícil de ler. Melhor dizer exatamente qual coluna divergiu.
    """
    existing = [f.name for f in spark.table(f"{CATALOG}.{namespace}.{table}").schema.fields]
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
    spark.sql(f"INSERT OVERWRITE {CATALOG}.{namespace}.{table} SELECT * FROM {view}")


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
        MERGE INTO {CATALOG}.{namespace}.{table} AS target
        USING {view} AS source
        ON {on_clause}
        WHEN MATCHED THEN UPDATE SET {set_clause}
        WHEN NOT MATCHED THEN INSERT *
        """
    )


# ---------------------------------------------------------------------------
# Data Quality
# ---------------------------------------------------------------------------
#
# O portão usa Great Expectations, não o Glue Data Quality.
#
# A troca não foi por gosto: `awsgluedq` não existe fora do runtime gerenciado
# do Glue — nem na imagem oficial `aws-glue-libs` que a AWS publica para
# desenvolvimento local. Verificado importando: `awsglue`, `awsglue.transforms`
# e `awsglue.dynamicframe` estão lá; `awsgluedq` não. Com o DQDL, o portão de
# qualidade era a única parte da pipeline impossível de exercitar fora da AWS —
# justamente a parte cujo comportamento mais importa verificar.
#
# Ver ../adr/0007-portao-de-qualidade-que-roda-nos-dois-lugares.md.


def _rotulo(expectation) -> str:
    """Nome legível de uma expectation, para o log do portão."""
    cfg = getattr(expectation, "configuration", None)
    coluna = getattr(expectation, "column", None)
    nome = type(expectation).__name__
    return f"{nome}({coluna})" if coluna else nome


def evaluate_data_quality(df, context_name, expectations):
    """Avalia uma lista de expectations e devolve (reprovadas, todas).

    Recebe um DataFrame comum do Spark: o portão não depende mais do
    GlueContext, e por isso roda igual na AWS e no lakehouse local.
    """
    import great_expectations as gx

    ctx = gx.get_context(mode="ephemeral")
    fonte = ctx.data_sources.add_spark(context_name)
    ativo = fonte.add_dataframe_asset(context_name)
    lote = ativo.add_batch_definition_whole_dataframe("lote").get_batch(
        batch_parameters={"dataframe": df}
    )

    resultados = [(_rotulo(e), lote.validate(e).success) for e in expectations]
    reprovadas = [rotulo for rotulo, ok in resultados if not ok]
    return reprovadas, resultados


def run_data_quality_gate(tables, rulesets, context_prefix):
    """Roda o DQ em várias tabelas e **falha o job** se alguma regra reprovar.

    Sem este `raise`, o job terminava com sucesso mesmo com regra reprovada: o
    Step Functions seguia adiante e a pipeline ficava verde com dado ruim.
    Falhando aqui, o `Catch` da máquina de estado interrompe o resto.
    """
    todas_reprovadas = {}

    for nome_tabela, df in tables.items():
        print(f"Avaliando qualidade de: {nome_tabela}")
        reprovadas, resultados = evaluate_data_quality(
            df, f"{context_prefix}_{nome_tabela}", rulesets[nome_tabela]
        )

        for rotulo, ok in resultados:
            print(f"  [{'Passou' if ok else 'REPROVOU'}] {rotulo}")

        if reprovadas:
            todas_reprovadas[nome_tabela] = reprovadas

    if todas_reprovadas:
        detalhe = "\n".join(
            f"  {tabela}: {', '.join(regras)}"
            for tabela, regras in todas_reprovadas.items()
        )
        raise ValueError(f"Regras de qualidade reprovadas:\n{detalhe}")

    print("Todas as regras de qualidade passaram.")
