locals {
  jar_dir = "jars"
  jar_files = [
    "${local.jar_dir}/spark-sql-kafka-0-10_2.12-3.3.4.jar",
    "${local.jar_dir}/spark-avro_2.12-3.3.4.jar",
    "${local.jar_dir}/opensearch-spark-30_2.12-1.3.0.jar",
    "${local.jar_dir}/kafka-clients-3.5.2.jar",
    "${local.jar_dir}/commons-pool2-2.12.1.jar",
  ]

  checkpoint_path = "s3://${var.s3_bucket_logs}/spark-checkpoints/${var.environment}/webevents-streaming"
}

# A senha do OpenSearch vai para o Secrets Manager, não para os argumentos do
# job: argumento de Glue job fica em texto claro no console e é legível por
# qualquer principal com glue:GetJob. O job recebe só o ARN.
resource "aws_secretsmanager_secret" "opensearch" {
  name                    = "dataeng-sandbox/${var.environment}/opensearch"
  description             = "Credenciais do OpenSearch usadas pelo job de streaming"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "opensearch" {
  secret_id = aws_secretsmanager_secret.opensearch.id
  secret_string = jsonencode({
    username = "admin"
    password = var.opensearch_password
  })
}

module "glue_jobs_streaming" {
  source = "../../modules/glue-job"

  project_name       = "dataeng-sandbox-webevents-streaming"
  environment        = var.environment
  region             = var.region
  s3_bucket_scripts  = var.s3_bucket_scripts
  data_buckets       = [var.s3_bucket_raw, var.s3_bucket_logs]
  scripts_local_path = "scripts"

  # gluestreaming, não glueetl: um job de Structured Streaming roda
  # indefinidamente e morreria no timeout de um job em lote.
  job_type = "streaming"

  job_scripts = {
    "dataeng-sandbox-webevents-streaming-kafka-opensearch" = "dataeng-sandbox-webevents-streaming-kafka-opensearch.py",
  }

  jar_files  = local.jar_files
  extra_jars = join(",", [for j in local.jar_files : "s3://${var.s3_bucket_scripts}/jars/${basename(j)}"])

  readable_secret_arns = [aws_secretsmanager_secret.opensearch.arn]

  worker_type       = "G.025X"
  number_of_workers = 2
  max_retries       = 0
  glue_version      = "4.0"

  additional_arguments = {
    "--user-jars-first"       = "true"
    "--OPENSEARCH_SECRET_ARN" = aws_secretsmanager_secret.opensearch.arn
    "--STREAMING_HOST"        = var.streaming_host
    "--KAFKA_TOPIC"           = var.kafka_topic
    "--OPENSEARCH_INDEX"      = "${var.opensearch_index}-${var.environment}"
    "--CHECKPOINT_PATH"       = local.checkpoint_path
  }
}
