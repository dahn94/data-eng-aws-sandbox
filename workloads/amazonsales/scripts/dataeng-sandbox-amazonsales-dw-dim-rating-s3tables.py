"""Dimensão de avaliação, derivada da tabela de staging."""

from glue_common import create_spark_session, get_args, read_table, write_table
from pyspark.sql.functions import regexp_replace


def main():
    args = get_args(
        ["stg_table_sales", "output_table", "s3_tables_bucket_arn", "namespace_destino"]
    )

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-dim-rating")

    df_dim_rating = read_table(spark, args["stg_table_sales"]).select(
        "user_id",
        "product_id",
        # A origem usa vírgula como separador decimal em alguns registros.
        regexp_replace("rating", ",", ".").cast("decimal(3,2)").alias("rating"),
        regexp_replace("rating_count", ",", ".").cast("bigint").alias("rating_count"),
    )

    write_table(spark, df_dim_rating, args["namespace_destino"], args["output_table"])


if __name__ == "__main__":
    main()
