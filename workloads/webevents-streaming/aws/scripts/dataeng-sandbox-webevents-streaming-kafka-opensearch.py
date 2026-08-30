"""Lê o CDC de web_events do Kafka (Avro/Debezium) e grava no OpenSearch.

Roda como job `gluestreaming`: fica vivo consumindo micro-batches até ser
parado. Todos os endereços, índices e caminhos vêm por argumento — nada de
bucket ou host fixo no código.

A senha do OpenSearch NÃO chega por argumento: argumento de Glue job é
visível em texto claro no console. O job recebe o ARN de um secret e busca o
valor em runtime.
"""

import json
import sys

import boto3
import requests
from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.avro.functions import from_avro

# Colunas do fake_web_events que não interessam ao índice e que carregam dado
# pessoal (IP, user agent). Removidas antes de sair do job.
COLS_TO_DROP = [
    "ip_address",
    "browser_name",
    "browser_user_agent",
    "browser_language",
    "os",
    "os_name",
    "device_type",
    "device_is_mobile",
    "user_custom_id",
]


def get_spark_session():
    return GlueContext(SparkContext()).spark_session


def get_opensearch_credentials(secret_arn: str) -> dict:
    """Lê usuário e senha do Secrets Manager."""
    client = boto3.client("secretsmanager")
    secret = client.get_secret_value(SecretId=secret_arn)
    return json.loads(secret["SecretString"])


def get_avro_schema(schema_registry: str, topic: str) -> str:
    url = f"{schema_registry}/subjects/{topic}-value/versions/latest/schema"
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    return response.text


def read_from_kafka(spark, kafka_bootstrap: str, topic: str):
    return (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", kafka_bootstrap)
        .option("subscribe", topic)
        .option("startingOffsets", "earliest")
        .option("failOnDataLoss", "false")
        .load()
    )


def decode_avro(df, schema_json: str):
    # O Confluent prefixa cada mensagem com 1 byte mágico + 4 bytes de schema
    # id; o from_avro do Spark espera o payload puro.
    value_bytes = F.expr("substring(value, 6, length(value)-5)")
    return df.select(from_avro(value_bytes, schema_json).alias("data"))


def transform_data(decoded_df):
    # No envelope do Debezium, delete traz o registro em `before` e o resto em
    # `after`.
    final_df = decoded_df.select(
        F.when(F.col("data.op") == "d", F.col("data.before"))
        .otherwise(F.col("data.after"))
        .alias("row"),
        "data.op",
        "data.ts_ms",
    ).select("row.*", "op", "ts_ms")

    final_df = final_df.withColumn(
        "event_timestamp",
        F.to_timestamp(F.col("event_timestamp"), "yyyy-MM-dd HH:mm:ss.SSSSSS"),
    )

    return final_df.drop(*COLS_TO_DROP)


def write_to_opensearch(df, host, index, user, password, checkpoint_path):
    return (
        df.writeStream.format("opensearch")
        .option("opensearch.nodes", f"https://{host}:9200")
        .option("opensearch.index.auto.create", "true")
        .option("opensearch.resource", index)
        .option("opensearch.net.http.auth.user", user)
        .option("opensearch.net.http.auth.pass", password)
        .option("opensearch.nodes.wan.only", "true")
        .option("opensearch.net.ssl", "true")
        # O OpenSearch de platform/local sobe com certificado autoassinado.
        .option("opensearch.net.ssl.cert.allow.self.signed", "true")
        .option("checkpointLocation", checkpoint_path)
        .outputMode("append")
        .start()
    )


def main():
    args = getResolvedOptions(
        sys.argv,
        [
            "OPENSEARCH_SECRET_ARN",
            "STREAMING_HOST",
            "KAFKA_TOPIC",
            "OPENSEARCH_INDEX",
            "CHECKPOINT_PATH",
        ],
    )

    host = args["STREAMING_HOST"]
    kafka_bootstrap = f"{host}:29092"
    schema_registry = f"http://{host}:8081"

    credentials = get_opensearch_credentials(args["OPENSEARCH_SECRET_ARN"])

    spark = get_spark_session()
    schema_json = get_avro_schema(schema_registry, args["KAFKA_TOPIC"])

    kafka_df = read_from_kafka(spark, kafka_bootstrap, args["KAFKA_TOPIC"])
    transformed_df = transform_data(decode_avro(kafka_df, schema_json))

    query = write_to_opensearch(
        transformed_df,
        host,
        args["OPENSEARCH_INDEX"],
        credentials["username"],
        credentials["password"],
        args["CHECKPOINT_PATH"],
    )
    query.awaitTermination()


if __name__ == "__main__":
    main()
