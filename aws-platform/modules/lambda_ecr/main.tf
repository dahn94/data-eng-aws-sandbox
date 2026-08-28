data "aws_partition" "current" {}

resource "aws_lambda_function" "python_lambda" {
  function_name = var.function_name
  description   = var.description
  role          = aws_iam_role.lambda_role.arn
  timeout       = var.timeout
  memory_size   = var.memory_size

  package_type = "Image"
  image_uri    = var.image_uri

  ephemeral_storage {
    size = var.ephemeral_storage_size
  }

  environment {
    variables = var.environment_variables
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
}

resource "aws_lambda_function_url" "lambda_url" {
  count              = var.create_function_url ? 1 : 0
  function_name      = aws_lambda_function.python_lambda.function_name
  authorization_type = var.function_url_auth_type

  # allow_credentials com allow_origins = ["*"] é rejeitado pelos navegadores e
  # é um antipadrão de CORS. Credenciais só quando há origem explícita.
  dynamic "cors" {
    for_each = length(var.allowed_origins) > 0 ? [1] : []
    content {
      allow_credentials = !contains(var.allowed_origins, "*")
      allow_origins     = var.allowed_origins
      allow_methods     = ["GET", "POST"]
      allow_headers     = ["content-type", "authorization", "x-amz-date", "x-amz-security-token"]
      max_age           = 86400
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

locals {
  bucket_statements = length(var.readable_buckets) > 0 ? [{
    Sid    = "ReadProjectBuckets"
    Effect = "Allow"
    Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
    Resource = concat(
      [for b in var.readable_buckets : "arn:${data.aws_partition.current.partition}:s3:::${b}"],
      [for b in var.readable_buckets : "arn:${data.aws_partition.current.partition}:s3:::${b}/*"],
    )
  }] : []

  s3tables_statements = var.s3tables_bucket_arn != "" ? [{
    Sid    = "ReadS3Tables"
    Effect = "Allow"
    Action = [
      "s3tables:GetTableBucket",
      "s3tables:ListNamespaces",
      "s3tables:GetNamespace",
      "s3tables:ListTables",
      "s3tables:GetTable",
      "s3tables:GetTableData",
      "s3tables:GetTableMetadataLocation",
    ]
    Resource = [var.s3tables_bucket_arn, "${var.s3tables_bucket_arn}/*"]
  }] : []

  all_statements = concat(local.bucket_statements, local.s3tables_statements)
}

# Somente leitura, e só nos recursos deste projeto. A versão anterior dava
# s3:PutObject, s3:DeleteObject e s3tables:* em Resource = "*".
resource "aws_iam_policy" "data_access" {
  count = length(local.all_statements) > 0 ? 1 : 0

  name        = "${var.function_name}-data-access"
  description = "Read-only access to the data this function queries"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.all_statements
  })
}

resource "aws_iam_role_policy_attachment" "data_access" {
  count = length(local.all_statements) > 0 ? 1 : 0

  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.data_access[0].arn
}

resource "aws_iam_role_policy_attachment" "additional_policies" {
  for_each   = toset(var.additional_policy_arns)
  role       = aws_iam_role.lambda_role.name
  policy_arn = each.value
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
}
