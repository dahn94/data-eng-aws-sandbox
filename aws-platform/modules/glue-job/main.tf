data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # Tudo que este módulo cria leva o ambiente no nome. Sem isso, aplicar dev e
  # prod na mesma conta colide no nome da IAM role e sobrescreve os jobs — a
  # separação por state e por tfvars viraria decorativa.
  name_prefix = "${var.project_name}-${var.environment}"

  # Nome real de cada job na AWS, a partir da chave lógica em job_scripts.
  job_names = { for k, v in var.job_scripts : k => "${k}-${var.environment}" }

  script_prefix = "glue_jobs_scripts/${var.environment}"

  # Módulo Python compartilhado pelos scripts, enviado como --extra-py-files.
  shared_py_key = var.shared_python_file != "" ? "${local.script_prefix}/_shared/${basename(var.shared_python_file)}" : ""
  shared_py_uri = var.shared_python_file != "" ? "s3://${var.s3_bucket_scripts}/${local.shared_py_key}" : ""

  extra_py_files = join(",", compact([local.shared_py_uri, var.extra_py_files]))

  # Statement só existe quando há um bucket S3 Tables: um Statement com
  # Resource = [] é rejeitado pela IAM.
  s3tables_statement = var.s3tables_bucket_arn == "" ? [] : [{
    Sid    = "S3TablesLakehouse"
    Effect = "Allow"
    Action = [
      "s3tables:GetTableBucket",
      "s3tables:ListNamespaces",
      "s3tables:CreateNamespace",
      "s3tables:GetNamespace",
      "s3tables:ListTables",
      "s3tables:CreateTable",
      "s3tables:GetTable",
      "s3tables:GetTableData",
      "s3tables:PutTableData",
      "s3tables:UpdateTableMetadataLocation",
      "s3tables:GetTableMetadataLocation",
    ]
    Resource = [var.s3tables_bucket_arn, "${var.s3tables_bucket_arn}/*"]
  }]

  bucket_arns = concat(
    [for b in var.data_buckets : "arn:${data.aws_partition.current.partition}:s3:::${b}"],
    [for b in var.data_buckets : "arn:${data.aws_partition.current.partition}:s3:::${b}/*"],
    ["arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_scripts}",
    "arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_scripts}/*"],
  )
}

resource "aws_iam_role" "glue_job_role" {
  name = "${local.name_prefix}-glue-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Permissões limitadas aos buckets deste projeto e ao catálogo desta conta.
# A versão anterior usava Resource = "*" com s3:*, glue:* e s3tables:*.
resource "aws_iam_policy" "glue_job_policy" {
  name        = "${local.name_prefix}-glue-job-policy"
  description = "Scoped policy for the ${local.name_prefix} Glue jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "ProjectBucketsOnly"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = local.bucket_arns
      },
      {
        Sid    = "GlueLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:AssociateKmsKey",
        ]
        Resource = ["arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"]
      },
      {
        Sid    = "GlueCatalogThisAccount"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchCreatePartition",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:glue:${var.region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:${data.aws_partition.current.partition}:glue:${var.region}:${data.aws_caller_identity.current.account_id}:database/*",
          "arn:${data.aws_partition.current.partition}:glue:${var.region}:${data.aws_caller_identity.current.account_id}:table/*",
        ]
      },
    ], local.s3tables_statement)
  })
}

resource "aws_iam_role_policy_attachment" "glue_job_policy_attachment" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = aws_iam_policy.glue_job_policy.arn
}

resource "aws_iam_role_policy_attachment" "glue_service_policy_attachment" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Secrets que os jobs podem ler. O job recebe o ARN como argumento e busca o
# valor em runtime — argumento de Glue job fica em texto claro no console.
resource "aws_iam_policy" "glue_secrets" {
  count = length(var.readable_secret_arns) > 0 ? 1 : 0

  name        = "${local.name_prefix}-glue-secrets-policy"
  description = "Read access to the secrets used by the ${local.name_prefix} jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.readable_secret_arns
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_secrets" {
  count = length(var.readable_secret_arns) > 0 ? 1 : 0

  role       = aws_iam_role.glue_job_role.name
  policy_arn = aws_iam_policy.glue_secrets[0].arn
}

# ---------------------------------------------------------------------------
# Scripts
# ---------------------------------------------------------------------------
resource "aws_s3_object" "glue_script" {
  for_each = var.job_scripts

  bucket = var.s3_bucket_scripts
  key    = "${local.script_prefix}/${each.key}/${each.value}"
  source = "${var.scripts_local_path}/${each.value}"
  etag   = filemd5("${var.scripts_local_path}/${each.value}")
}

# Funções comuns aos scripts, para não repetir create_spark_session e amigos
# em cada arquivo.
resource "aws_s3_object" "shared_python" {
  count = var.shared_python_file != "" ? 1 : 0

  bucket = var.s3_bucket_scripts
  key    = local.shared_py_key
  source = "${var.scripts_local_path}/${var.shared_python_file}"
  etag   = filemd5("${var.scripts_local_path}/${var.shared_python_file}")
}

# Jars que os jobs precisam, versionados junto do repositório e enviados por
# Terraform — antes eram um upload manual não documentado.
resource "aws_s3_object" "jar" {
  for_each = toset(var.jar_files)

  bucket = var.s3_bucket_scripts
  key    = "jars/${basename(each.value)}"
  source = each.value
  etag   = filemd5(each.value)
}

# ---------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------
resource "aws_glue_job" "glue_job" {
  for_each = var.job_scripts

  name              = local.job_names[each.key]
  role_arn          = aws_iam_role.glue_job_role.arn
  glue_version      = var.glue_version
  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  max_retries       = var.max_retries

  # Job de streaming roda indefinidamente: timeout aqui seria uma morte
  # programada. Só job em lote recebe timeout.
  timeout = var.job_type == "streaming" ? null : var.timeout

  command {
    # glueetl roda em lote e termina; gluestreaming mantém o micro-batch vivo.
    # Usar glueetl num job de Structured Streaming faz o job morrer no timeout.
    name            = var.job_type == "streaming" ? "gluestreaming" : "glueetl"
    script_location = "s3://${var.s3_bucket_scripts}/${local.script_prefix}/${each.key}/${each.value}"
    python_version  = "3"
  }

  default_arguments = merge(
    {
      "--enable-glue-datacatalog"          = "true"
      "--enable-spark-ui"                  = "true"
      "--spark-event-logs-path"            = "s3://${var.s3_bucket_scripts}/spark-logs/${var.environment}/"
      "--enable-metrics"                   = "true"
      "--enable-continuous-cloudwatch-log" = "true"
      "--job-language"                     = "python"
      "--TempDir"                          = "s3://${var.s3_bucket_scripts}/glue_jobs_temp/${var.environment}/"
      "--ENVIRONMENT"                      = var.environment
    },
    # Auto scaling não se aplica a job de streaming.
    var.job_type == "streaming" ? {} : { "--enable-auto-scaling" = "true" },
    local.extra_py_files != "" ? { "--extra-py-files" = local.extra_py_files } : {},
    var.additional_python_modules != "" ? { "--additional-python-modules" = var.additional_python_modules } : {},
    var.extra_jars != "" ? { "--extra-jars" = var.extra_jars } : {},
    var.additional_arguments,
  )

  execution_property {
    max_concurrent_runs = var.max_concurrent_runs
  }

  depends_on = [aws_s3_object.shared_python, aws_s3_object.jar]
}
