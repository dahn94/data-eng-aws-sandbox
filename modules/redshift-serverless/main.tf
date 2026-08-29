# Redshift Serverless em duas peças, de propósito separadas pela AWS:
#
#   namespace  = os dados e a identidade (banco, usuários, snapshots, datashares)
#   workgroup  = a capacidade de computação que atende consulta
#
# A separação é o que torna datashare possível dentro da mesma conta: dois
# namespaces distintos podem compartilhar sem cópia. Ver workloads/data-sharing.

resource "aws_redshiftserverless_namespace" "this" {
  namespace_name = var.name

  db_name             = var.database_name
  admin_username      = var.admin_username
  admin_user_password = var.admin_password

  iam_roles            = var.iam_role_arns
  default_iam_role_arn = var.default_iam_role_arn

  log_exports = var.log_exports

  tags = {
    Name = var.name
  }
}

resource "aws_redshiftserverless_workgroup" "this" {
  namespace_name = aws_redshiftserverless_namespace.this.namespace_name
  workgroup_name = var.name

  base_capacity        = var.base_capacity_rpu
  max_capacity         = var.max_capacity_rpu != -1 ? var.max_capacity_rpu : null
  publicly_accessible  = var.publicly_accessible
  enhanced_vpc_routing = var.enhanced_vpc_routing

  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  # `config_parameter` aceita só um conjunto fechado de chaves, e o valor é
  # string mesmo quando representa booleano.
  config_parameter {
    parameter_key   = "enable_case_sensitive_identifier"
    parameter_value = tostring(var.case_sensitive_identifier)
  }

  tags = {
    Name = var.name
  }
}
