"""Fato: valor de vendas por usuário e categoria."""

from glue_common import create_spark_session, get_args, read_table, write_table
from pyspark.sql.functions import col, regexp_replace
from pyspark.sql.functions import sum as _sum


def build_fact(spark, stg_table_sales, dim_product_table, dim_user_table):
    df_stg_sales = read_table(spark, stg_table_sales)
    df_dim_product = read_table(spark, dim_product_table)
    df_dim_user = read_table(spark, dim_user_table)

    # Os preços vêm com símbolo de moeda e separador de milhar.
    df_limpo = df_stg_sales.withColumn(
        "actual_price_clean",
        regexp_replace("actual_price", "[^0-9.]", "").cast("decimal(10,2)"),
    )

    return (
        df_limpo.alias("s")
        .join(df_dim_product.alias("p"), col("s.product_id") == col("p.product_id"))
        .join(df_dim_user.alias("u"), col("s.user_id") == col("u.user_id"))
        .groupBy("u.user_id", "p.category")
        .agg(_sum("actual_price_clean").alias("sales_amount"))
        .select("user_id", "category", "sales_amount")
    )


def main():
    args = get_args(
        [
            "stg_table_sales",
            "dim_product_table",
            "dim_user_table",
            "output_table",
            "s3_tables_bucket_arn",
            "namespace_destino",
        ]
    )

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-fact-sales")

    df_result = build_fact(
        spark,
        args["stg_table_sales"],
        args["dim_product_table"],
        args["dim_user_table"],
    )

    write_table(spark, df_result, args["namespace_destino"], args["output_table"])


if __name__ == "__main__":
    main()
