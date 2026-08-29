"""Staging: lê o Parquet bruto que o DMS gravou e faz upsert na tabela staged."""

from glue_common import create_spark_session, get_args, merge_table
from pyspark.sql.functions import col
from pyspark.sql.types import DoubleType, IntegerType, StringType

# Tipos da tabela de vendas. Explícito de propósito: inferir do Parquet faz o
# schema da tabela Iceberg mudar sozinho quando a origem muda.
COLUMN_TYPES = {
    "product_id": StringType(),
    "product_name": StringType(),
    "category": StringType(),
    "discounted_price": DoubleType(),
    "actual_price": DoubleType(),
    "discount_percentage": DoubleType(),
    "rating": DoubleType(),
    "rating_count": IntegerType(),
    "about_product": StringType(),
    "user_id": StringType(),
    "user_name": StringType(),
    "review_id": StringType(),
    "review_title": StringType(),
    "review_content": StringType(),
    "img_link": StringType(),
    "product_link": StringType(),
}


def cast_columns(df):
    for name, dtype in COLUMN_TYPES.items():
        df = df.withColumn(name, col(name).cast(dtype))
    return df.select(*COLUMN_TYPES.keys())


def main():
    args = get_args(
        ["iceberg_table", "primary_key", "s3_tables_bucket_arn", "namespace", "input_path"]
    )

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-stg")

    df = spark.read.parquet(args["input_path"])
    df = cast_columns(df).dropDuplicates([args["primary_key"]])

    merge_table(spark, df, args["namespace"], args["iceberg_table"], args["primary_key"])


if __name__ == "__main__":
    main()
