"""Dimensão de produto, derivada da tabela de staging."""

from glue_common import create_spark_session, get_args, read_table, write_table


def main():
    args = get_args(
        ["stg_table_sales", "output_table", "s3_tables_bucket_arn", "namespace_destino"]
    )

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-dim-product")

    df_dim_product = read_table(spark, args["stg_table_sales"]).select(
        "product_id",
        "product_name",
        "category",
        "about_product",
        "img_link",
        "product_link",
    ).distinct()

    write_table(spark, df_dim_product, args["namespace_destino"], args["output_table"])


if __name__ == "__main__":
    main()
