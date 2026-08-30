"""Data Quality dos fatos. Falha o job — e a pipeline — se uma regra reprovar."""

import great_expectations.expectations as gxe

from glue_common import create_spark_session, get_args, read_table, run_data_quality_gate

# As mesmas regras que estavam em DQDL, agora em Great Expectations. O DQDL era
# um DSL só do Glue; estas expectations rodam igual aqui e no lakehouse local.
RULESETS = {
    "fact_product_rating": [
        gxe.ExpectColumnToExist(column="product_id"),
        gxe.ExpectColumnToExist(column="product_name"),
        gxe.ExpectColumnToExist(column="avg_rating"),
        gxe.ExpectColumnValuesToNotBeNull(column="product_id"),
        gxe.ExpectColumnValuesToNotBeNull(column="product_name"),
        gxe.ExpectColumnValuesToNotBeNull(column="avg_rating"),
        gxe.ExpectColumnValuesToBeOfType(column="product_id", type_="StringType"),
        gxe.ExpectColumnValuesToBeOfType(column="product_name", type_="StringType"),
        gxe.ExpectTableRowCountToBeBetween(min_value=1),
        gxe.ExpectColumnValuesToBeBetween(column="avg_rating", min_value=0, max_value=5),
    ],
    "fact_sales_category": [
        gxe.ExpectColumnToExist(column="user_id"),
        gxe.ExpectColumnToExist(column="category"),
        gxe.ExpectColumnToExist(column="sales_amount"),
        gxe.ExpectColumnValuesToNotBeNull(column="user_id"),
        gxe.ExpectColumnValuesToNotBeNull(column="category"),
        gxe.ExpectColumnValuesToNotBeNull(column="sales_amount"),
        gxe.ExpectColumnValuesToBeOfType(column="user_id", type_="StringType"),
        gxe.ExpectColumnValuesToBeOfType(column="category", type_="StringType"),
        gxe.ExpectTableRowCountToBeBetween(min_value=1),
    ],
}


def main():
    args = get_args(["s3_tables_bucket_arn", "namespace"])

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-facts-dq")

    namespace = args["namespace"]
    # Cada fato lê a sua própria tabela. A versão anterior lia
    # fact_product_rating nas duas entradas, então o ruleset de
    # fact_sales_category era avaliado contra a tabela errada.
    tables = {name: read_table(spark, f"{namespace}.{name}") for name in RULESETS}

    run_data_quality_gate(tables, RULESETS, context_prefix="amazonsales_lakehouse")


if __name__ == "__main__":
    main()
