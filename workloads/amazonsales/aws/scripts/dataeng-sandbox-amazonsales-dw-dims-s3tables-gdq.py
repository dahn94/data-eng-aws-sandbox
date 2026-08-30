"""Data Quality das dimensões.

Este job é o portão entre as dimensões e os fatos: se uma regra falhar, ele
falha, e o `Catch` da máquina de estado interrompe a pipeline antes que os
fatos sejam construídos sobre dado ruim.
"""

import great_expectations.expectations as gxe

from glue_common import create_spark_session, get_args, read_table, run_data_quality_gate

# As mesmas regras que estavam em DQDL, agora em Great Expectations. O DQDL era
# um DSL só do Glue; estas expectations rodam igual aqui e no lakehouse local.
#
# `Uniqueness "col" > 0.99` virou ExpectColumnProportionOfUniqueValuesToBeBetween
# com min_value=0.99: é a tradução literal, e não uma unicidade estrita.
RULESETS = {
    "dim_user": [
        gxe.ExpectColumnToExist(column="user_id"),
        gxe.ExpectColumnToExist(column="user_name"),
        gxe.ExpectColumnValuesToNotBeNull(column="user_id"),
        gxe.ExpectColumnValuesToNotBeNull(column="user_name"),
        gxe.ExpectColumnProportionOfUniqueValuesToBeBetween(column="user_id", min_value=0.99),
        gxe.ExpectTableRowCountToBeBetween(min_value=1),
        gxe.ExpectColumnValuesToBeOfType(column="user_id", type_="StringType"),
        gxe.ExpectColumnValuesToBeOfType(column="user_name", type_="StringType"),
    ],
    "dim_product": [
        gxe.ExpectColumnToExist(column="product_id"),
        gxe.ExpectColumnToExist(column="product_name"),
        gxe.ExpectColumnToExist(column="category"),
        gxe.ExpectColumnToExist(column="about_product"),
        gxe.ExpectColumnToExist(column="img_link"),
        gxe.ExpectColumnToExist(column="product_link"),
        gxe.ExpectColumnValuesToNotBeNull(column="product_id"),
        gxe.ExpectColumnValuesToNotBeNull(column="product_name"),
        gxe.ExpectColumnValuesToNotBeNull(column="category"),
        gxe.ExpectColumnValuesToNotBeNull(column="img_link"),
        gxe.ExpectColumnValuesToNotBeNull(column="product_link"),
        gxe.ExpectColumnProportionOfUniqueValuesToBeBetween(column="product_id", min_value=0.99),
        gxe.ExpectTableRowCountToBeBetween(min_value=1),
        gxe.ExpectColumnValuesToBeOfType(column="product_id", type_="StringType"),
        gxe.ExpectColumnValuesToBeOfType(column="product_name", type_="StringType"),
        gxe.ExpectColumnValuesToBeOfType(column="category", type_="StringType"),
        gxe.ExpectColumnValuesToBeOfType(column="about_product", type_="StringType"),
        gxe.ExpectColumnValuesToBeOfType(column="img_link", type_="StringType"),
        gxe.ExpectColumnValuesToBeOfType(column="product_link", type_="StringType"),
    ],
    "dim_rating": [
        gxe.ExpectColumnToExist(column="user_id"),
        gxe.ExpectColumnToExist(column="product_id"),
        gxe.ExpectColumnToExist(column="rating"),
        gxe.ExpectColumnToExist(column="rating_count"),
        gxe.ExpectColumnValuesToNotBeNull(column="user_id"),
        gxe.ExpectColumnValuesToNotBeNull(column="product_id"),
        gxe.ExpectColumnValuesToBeOfType(column="user_id", type_="StringType"),
        gxe.ExpectColumnValuesToBeOfType(column="product_id", type_="StringType"),
        gxe.ExpectTableRowCountToBeBetween(min_value=1),
    ],
}


def main():
    args = get_args(["s3_tables_bucket_arn", "namespace"])

    spark = create_spark_session(args["s3_tables_bucket_arn"], "amazonsales-dims-dq")

    namespace = args["namespace"]
    tables = {name: read_table(spark, f"{namespace}.{name}") for name in RULESETS}

    run_data_quality_gate(tables, RULESETS, context_prefix="amazonsales_lakehouse")


if __name__ == "__main__":
    main()
