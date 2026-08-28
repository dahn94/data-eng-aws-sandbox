"""Data Quality dos fatos. Falha o job — e a pipeline — se uma regra reprovar."""

from awsglue.context import GlueContext
from glue_common import create_spark_session, get_args, read_table, run_data_quality_gate

RULESETS = {
    "fact_product_rating": """
        Rules = [
            ColumnExists "product_id",
            ColumnExists "product_name",
            ColumnExists "avg_rating",
            IsComplete "product_id",
            IsComplete "product_name",
            IsComplete "avg_rating",
            ColumnDataType "product_id" = "string",
            ColumnDataType "product_name" = "string",
            RowCount > 0,
            ColumnValues "avg_rating" between 0 and 5
        ]
    """,
    "fact_sales_category": """
        Rules = [
            ColumnExists "user_id",
            ColumnExists "category",
            ColumnExists "sales_amount",
            IsComplete "user_id",
            IsComplete "category",
            IsComplete "sales_amount",
            ColumnDataType "user_id" = "string",
            ColumnDataType "category" = "string",
            RowCount > 0
        ]
    """,
}


def main():
    args = get_args(["s3_tables_bucket_arn", "namespace", "dq_results_path"])

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-facts-dq")
    glue_context = GlueContext(spark.sparkContext)

    namespace = args["namespace"]
    # Cada fato lê a sua própria tabela. A versão anterior lia
    # fact_product_rating nas duas entradas, então o ruleset de
    # fact_sales_category era avaliado contra a tabela errada.
    tables = {name: read_table(spark, f"{namespace}.{name}") for name in RULESETS}

    run_data_quality_gate(
        tables,
        glue_context,
        RULESETS,
        context_prefix="amazonsales_lakehouse",
        results_s3_prefix=args["dq_results_path"],
    )


if __name__ == "__main__":
    main()
