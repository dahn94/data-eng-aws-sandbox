variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos IAM criados"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, prod). Entra no nome de todos os recursos para que ambientes não colidam na mesma conta."
  type        = string
}

variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-2"
}

variable "job_type" {
  description = "'etl' para job em lote (glueetl) ou 'streaming' para Structured Streaming (gluestreaming)."
  type        = string
  default     = "etl"

  validation {
    condition     = contains(["etl", "streaming"], var.job_type)
    error_message = "job_type deve ser 'etl' ou 'streaming'."
  }
}

variable "s3_bucket_scripts" {
  description = "Bucket S3 onde os scripts, jars e logs do Spark ficam"
  type        = string
}

variable "data_buckets" {
  description = "Buckets de dados que os jobs deste módulo podem ler e escrever. A policy IAM é limitada a esta lista."
  type        = list(string)
  default     = []
}

variable "s3tables_bucket_arn" {
  description = "ARN do bucket S3 Tables que os jobs acessam. Vazio = nenhuma permissão de s3tables é concedida."
  type        = string
  default     = ""
}

variable "readable_secret_arns" {
  description = "ARNs de secrets do Secrets Manager que os jobs podem ler"
  type        = list(string)
  default     = []
}

variable "scripts_local_path" {
  description = "Caminho local onde os scripts do Glue estão"
  type        = string
  default     = "scripts"
}

variable "job_scripts" {
  description = "Mapa {nome_lógico_do_job = nome_do_arquivo}. O nome real na AWS ganha o sufixo do ambiente."
  type        = map(string)
}

variable "shared_python_file" {
  description = "Arquivo Python com as funções comuns aos scripts, relativo a scripts_local_path. Enviado ao S3 e passado em --extra-py-files."
  type        = string
  default     = ""
}

variable "jar_files" {
  description = "Caminhos locais de jars a enviar para s3://<scripts>/jars/. Deixe vazio se os jars já estiverem lá."
  type        = list(string)
  default     = []
}

variable "worker_type" {
  description = "Tipo de worker do Glue (G.025X, G.1X, G.2X)"
  type        = string
  default     = "G.1X"
}

variable "number_of_workers" {
  description = "Número de workers do job"
  type        = number
  default     = 2
}

variable "timeout" {
  description = "Timeout em minutos. Ignorado quando job_type = 'streaming'."
  type        = number
  default     = 60
}

variable "max_retries" {
  description = "Número máximo de tentativas em caso de falha"
  type        = number
  default     = 0
}

variable "max_concurrent_runs" {
  description = "Número máximo de execuções concorrentes"
  type        = number
  default     = 1
}

variable "additional_python_modules" {
  description = "Módulos Python extras, separados por vírgula. Vazio = nenhum (o default anterior forçava pandas==1.5.3 em todo job)."
  type        = string
  default     = ""
}

variable "extra_py_files" {
  description = "Arquivos .py/.zip extras em S3, separados por vírgula. Somados ao shared_python_file."
  type        = string
  default     = ""
}

variable "extra_jars" {
  description = "Jars extras em S3, separados por vírgula"
  type        = string
  default     = ""
}

variable "additional_arguments" {
  description = "Argumentos adicionais do job. Não coloque segredos aqui: argumentos de Glue job são visíveis em texto claro no console."
  type        = map(string)
  default     = {}
}

variable "glue_version" {
  description = "Versão do Glue"
  type        = string
  default     = "5.0"
}
