"""Dimensão de usuário, derivada da tabela de staging."""

from glue_common import create_spark_session, get_args, read_table, write_table


def main():
    args = get_args(
        ["stg_table_sales", "output_table", "s3_tables_bucket_arn", "namespace_destino"]
    )

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-dim-user")

    df_dim_user = (
        read_table(spark, args["stg_table_sales"]).select("user_id", "user_name").distinct()
    )

    write_table(spark, df_dim_user, args["namespace_destino"], args["output_table"])


if __name__ == "__main__":
    main()
