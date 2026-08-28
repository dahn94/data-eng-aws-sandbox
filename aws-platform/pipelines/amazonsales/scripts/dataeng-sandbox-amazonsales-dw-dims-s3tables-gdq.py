"""Data Quality das dimensões.

Este job é o portão entre as dimensões e os fatos: se uma regra falhar, ele
falha, e o `Catch` da máquina de estado interrompe a pipeline antes que os
fatos sejam construídos sobre dado ruim.
"""

from awsglue.context import GlueContext
from glue_common import create_spark_session, get_args, read_table, run_data_quality_gate

RULESETS = {
    "dim_user": """
        Rules = [
            ColumnExists "user_id",
            ColumnExists "user_name",
            IsComplete "user_id",
            IsComplete "user_name",
            Uniqueness "user_id" > 0.99,
            RowCount > 0,
            ColumnDataType "user_id" = "string",
            ColumnDataType "user_name" = "string"
        ]
    """,
    "dim_product": """
        Rules = [
            ColumnExists "product_id",
            ColumnExists "product_name",
            ColumnExists "category",
            ColumnExists "about_product",
            ColumnExists "img_link",
            ColumnExists "product_link",
            IsComplete "product_id",
            IsComplete "product_name",
            IsComplete "category",
            IsComplete "img_link",
            IsComplete "product_link",
            Uniqueness "product_id" > 0.99,
            RowCount > 0,
            ColumnDataType "product_id" = "string",
            ColumnDataType "product_name" = "string",
            ColumnDataType "category" = "string",
            ColumnDataType "about_product" = "string",
            ColumnDataType "img_link" = "string",
            ColumnDataType "product_link" = "string"
        ]
    """,
    "dim_rating": """
        Rules = [
            ColumnExists "user_id",
            ColumnExists "product_id",
            ColumnExists "rating",
            ColumnExists "rating_count",
            IsComplete "user_id",
            IsComplete "product_id",
            ColumnDataType "user_id" = "string",
            ColumnDataType "product_id" = "string",
            RowCount > 0
        ]
    """,
}


def main():
    args = get_args(["s3_tables_bucket_arn", "namespace", "dq_results_path"])

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-dims-dq")
    glue_context = GlueContext(spark.sparkContext)

    namespace = args["namespace"]
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
