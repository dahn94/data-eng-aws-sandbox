"""Fato: nota média por produto, cruzando staging com as dimensões."""

from glue_common import create_spark_session, get_args, read_table, write_table
from pyspark.sql.functions import avg, col, regexp_extract


def build_fact(spark, stg_table_sales, dim_product_table, dim_rating_table):
    df_stg_sales = read_table(spark, stg_table_sales)
    df_dim_product = read_table(spark, dim_product_table)
    df_dim_rating = read_table(spark, dim_rating_table)

    # Descarta ratings não numéricos em vez de deixá-los virar null na média.
    df_dim_rating_valid = df_dim_rating.withColumn(
        "rating_num", regexp_extract("rating", "^[0-9.]+$", 0).cast("double")
    ).filter(col("rating_num").isNotNull())

    return (
        df_stg_sales.alias("s")
        .join(df_dim_product.alias("p"), col("s.product_id") == col("p.product_id"))
        .join(df_dim_rating_valid.alias("r"), col("r.product_id") == col("p.product_id"))
        .groupBy("p.product_id", "p.product_name")
        .agg(avg("r.rating_num").alias("avg_rating"))
        .select("product_id", "product_name", "avg_rating")
    )


def main():
    args = get_args(
        [
            "stg_table_sales",
            "dim_product_table",
            "dim_rating_table",
            "output_table",
            "s3_tables_bucket_arn",
            "namespace_destino",
        ]
    )

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-fact-rating")

    df_result = build_fact(
        spark,
        args["stg_table_sales"],
        args["dim_product_table"],
        args["dim_rating_table"],
    )

    write_table(spark, df_result, args["namespace_destino"], args["output_table"])


if __name__ == "__main__":
    main()
