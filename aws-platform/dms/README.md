# aws-platform/dms

Root module do DMS: endpoints (source Postgres / target S3), instância de
replicação e a task `full-load-and-cdc`. Depende dos states de
`aws-platform/network` e `aws-platform/rds` — aplique nessa ordem.

## Aplicar

```bash
cd aws-platform/dms
terraform init -backend-config=backends/develop.hcl
export TF_VAR_rds_password='mesma-senha-do-aws-platform/rds'
terraform apply -var-file=envs/develop.tfvars
```

A task é criada mas **não inicia sozinha**. Inicie pelo console do DMS ou:

```bash
aws dms start-replication-task \
  --replication-task-arn "$(terraform output -raw replication_task_arn)" \
  --start-replication-task-type start-replication
```

## Onde os dados aparecem

```bash
terraform output s3_output_prefix
# s3://<prefixo>-lake-raw-dev/raw/postgres
```

O DMS grava em `<bucket_folder>/<schema>/<tabela>/`. Esse caminho é o contrato
com as pipelines: `raw_output_prefix` aqui precisa casar com `raw_input_prefix`
em `aws-platform/pipelines/amazonsales`. Se mudar um, mude o outro.

## Pré-requisitos que não são deste módulo

- O RDS precisa ter `rds.logical_replication = 1` — o módulo `rds` já
  configura, mas confirme que a instância **reiniciou** depois disso.
- A role `dms-vpc-role` é única por conta AWS. Se você já a tem (de outro
  projeto ou por ter usado o console do DMS antes), rode com
  `-var="create_vpc_role=false"`.

## Custo

`dms.t3.micro` + 20 GB ≈ **US$28/mês** rodando 24/7. A instância de replicação
**não tem "stop", só delete** — ao encerrar a sessão de estudo:

```bash
terraform destroy -var-file=envs/develop.tfvars
```

Se estiver usando Debezium (`local-services/streaming-cdc`) em vez do DMS, lembre
de também remover o connector antes de destruir o RDS — um replication slot
órfão prende o WAL e pode encher o storage.
