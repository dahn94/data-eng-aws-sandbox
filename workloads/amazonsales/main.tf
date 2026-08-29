data "aws_caller_identity" "current" {}

locals {
  # O bucket S3 Tables é criado por platform/aws/foundation, que roda com state
  # local — então não dá para lê-lo por terraform_remote_state. O nome é
  # determinístico, então o ARN é montado aqui e pode ser sobrescrito pela
  # variável se você usar outro nome.
  lakehouse_arn = var.lakehouse_arn != "" ? var.lakehouse_arn : "arn:aws:s3tables:${var.region}:${data.aws_caller_identity.current.account_id}:bucket/dataeng-sandbox-lakehouse-${var.environment}"

  raw_input       = "s3://${var.s3_bucket_raw}/${var.raw_input_prefix}"
  dq_results_path = "s3://${var.s3_bucket_curated}/data_quality_results/${var.environment}"
}

module "glue_jobs_s3tables" {
  source = "../../modules/glue-job"

  project_name        = "dataeng-sandbox-amazonsales"
  environment         = var.environment
  region              = var.region
  s3_bucket_scripts   = var.s3_bucket_scripts
  data_buckets        = [var.s3_bucket_raw, var.s3_bucket_curated]
  s3tables_bucket_arn = local.lakehouse_arn
  scripts_local_path  = "scripts"

  job_scripts = {
    "dataeng-sandbox-amazonsales-dw-table-stg-s3tables"           = "dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py",
    "dataeng-sandbox-amazonsales-dw-dim-product-s3tables"         = "dataeng-sandbox-amazonsales-dw-dim-product-s3tables.py",
    "dataeng-sandbox-amazonsales-dw-dim-rating-s3tables"          = "dataeng-sandbox-amazonsales-dw-dim-rating-s3tables.py",
    "dataeng-sandbox-amazonsales-dw-dim-user-s3tables"            = "dataeng-sandbox-amazonsales-dw-dim-user-s3tables.py",
    "dataeng-sandbox-amazonsales-dw-dims-s3tables-gdq"            = "dataeng-sandbox-amazonsales-dw-dims-s3tables-gdq.py",
    "dataeng-sandbox-amazonsales-dw-fact-product-rating-s3tables" = "dataeng-sandbox-amazonsales-dw-fact-product-rating-s3tables.py",
    "dataeng-sandbox-amazonsales-dw-fact-sales-category-s3tables" = "dataeng-sandbox-amazonsales-dw-fact-sales-category-s3tables.py",
    "dataeng-sandbox-amazonsales-dw-facts-s3tables-gdq"           = "dataeng-sandbox-amazonsales-dw-facts-s3tables-gdq.py",
  }

  # Funções comuns aos 8 scripts (sessão Spark, criação de namespace, escrita).
  # Enviadas ao S3 e injetadas via --extra-py-files.
  shared_python_file = "glue_common.py"

  # O jar do catálogo S3 Tables vive no repositório e é enviado pelo Terraform,
  # em vez de depender de um upload manual para um bucket que já existia.
  jar_files  = ["jars/${var.iceberg_catalog_jar_name}"]
  extra_jars = "s3://${var.s3_bucket_scripts}/jars/${var.iceberg_catalog_jar_name}"

  worker_type       = "G.1X"
  number_of_workers = 3
  timeout           = 60
  max_retries       = 0

  additional_arguments = {
    "--enable-glue-datacatalog" = "true"
    "--user-jars-first"         = "true"
    "--datalake-formats"        = "iceberg"
  }
}

module "step_functions" {
  source = "../../modules/step-functions"

  project_name = "dataeng-sandbox-amazonsales"
  environment  = var.environment
  region       = var.region

  state_machines = {
    "dataeng-sandbox-amazonsales-s3tables" = {
      definition_file = "sfn_definition_s3tables_amazonsales.json"
      type            = "STANDARD"
    }
  }

  # Valores injetados na definição JSON, que assim não carrega nenhum nome de
  # bucket nem ARN de conta.
  template_variables = {
    lakehouse_arn   = local.lakehouse_arn
    raw_input       = local.raw_input
    dq_results_path = local.dq_results_path
  }

  # A máquina de estado só pode disparar os jobs desta pipeline.
  glue_job_arns = values(module.glue_jobs_s3tables.glue_job_arns)

  log_retention_days     = 30
  include_execution_data = true
  logging_level          = "ALL"
}
