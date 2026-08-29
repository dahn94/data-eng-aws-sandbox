#!/usr/bin/env bash
# Baixa os jars que os jobs Glue e o Kafka Connect precisam.
#
# Eles não ficam versionados no repositório: são ~15 MB de binário que o Git
# guardaria para sempre, e todos vêm de repositórios públicos e estáveis.
# O Terraform envia para o S3 os que encontrar; o Kafka Connect monta os dele
# como volume.
#
#   ./scripts/fetch-jars.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAVEN="https://repo1.maven.org/maven2"

download() {
  local dest_dir="$1" url="$2"
  local file; file="$(basename "$url")"
  mkdir -p "$dest_dir"
  if [[ -f "$dest_dir/$file" ]]; then
    echo "  já existe: ${dest_dir#$REPO_ROOT/}/$file"
    return
  fi
  echo "  baixando:  ${dest_dir#$REPO_ROOT/}/$file"
  curl -fsSL --retry 3 -o "$dest_dir/$file" "$url"
}

echo "==> workloads/amazonsales (catálogo S3 Tables para Iceberg)"
download "$REPO_ROOT/workloads/amazonsales/jars" \
  "$MAVEN/software/amazon/s3tables/s3-tables-catalog-for-iceberg-runtime/0.1.7/s3-tables-catalog-for-iceberg-runtime-0.1.7.jar"

echo "==> workloads/webevents-streaming (Kafka + Avro + OpenSearch para Spark)"
WEB="$REPO_ROOT/workloads/webevents-streaming/jars"
download "$WEB" "$MAVEN/org/apache/spark/spark-sql-kafka-0-10_2.12/3.3.4/spark-sql-kafka-0-10_2.12-3.3.4.jar"
download "$WEB" "$MAVEN/org/apache/spark/spark-avro_2.12/3.3.4/spark-avro_2.12-3.3.4.jar"
download "$WEB" "$MAVEN/org/apache/kafka/kafka-clients/3.5.2/kafka-clients-3.5.2.jar"
download "$WEB" "$MAVEN/org/apache/commons/commons-pool2/2.12.1/commons-pool2-2.12.1.jar"
download "$WEB" "$MAVEN/org/opensearch/client/opensearch-spark-30_2.12/1.3.0/opensearch-spark-30_2.12-1.3.0.jar"

echo "==> local-services/streaming-cdc (Avro + Schema Registry para o Kafka Connect)"
CDC="$REPO_ROOT/local-services/streaming-cdc/jars/debezium"
CONFLUENT="https://packages.confluent.io/maven/io/confluent"
for artifact in kafka-connect-avro-converter kafka-connect-avro-data kafka-avro-serializer \
                kafka-schema-serializer kafka-schema-converter kafka-schema-registry-client \
                common-config common-utils; do
  download "$CDC" "$CONFLUENT/$artifact/8.0.0/$artifact-8.0.0.jar"
done

echo
echo "Pronto. Os jars ficam fora do Git (veja .gitignore) e são enviados"
echo "ao S3 pelo Terraform quando você aplicar os workloads."
