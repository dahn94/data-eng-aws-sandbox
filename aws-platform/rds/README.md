# aws-platform/rds

Root module do Postgres gerenciado (RDS). Depende do state de
`aws-platform/network` — aplique `foundation` → `network` → `rds`.

## Aplicar

```bash
cd aws-platform/rds
terraform init -backend-config=backends/develop.hcl
export TF_VAR_rds_password='uma-senha-forte'
terraform apply -var-file=envs/develop.tfvars
```

## Acesso de fora da VPC

O default de `allowed_cidr_blocks` é lista vazia: ninguém entra de fora. Para
conectar da sua máquina, coloque seu IP em `envs/develop.tfvars`:

```bash
curl -s https://checkip.amazonaws.com   # descobre seu IP
```

```hcl
allowed_cidr_blocks = ["203.0.113.10/32"]
```

Nunca use `0.0.0.0/0` aqui: a instância é `publicly_accessible`, e o security
group é a única coisa entre o seu banco e a internet.

O tráfego de dentro da VPC é sempre liberado — é o que permite ao DMS, que
roda em subnet privada, alcançar o banco.

## Replicação lógica (CDC)

O parameter group já vem com `rds.logical_replication = 1`,
`max_replication_slots` e `max_wal_senders`. Sem isso, tanto o DMS quanto o
Debezium fazem a carga inicial e depois **ficam parados para sempre, sem erro
claro** — é o problema de CDC mais comum e mais difícil de diagnosticar.

O parâmetro é estático, então o módulo usa `apply_immediately = true` para
reiniciar a instância na hora, em vez de esperar a janela de manutenção.

## Custo

`db.t4g.micro` + 20 GB gp3 ≈ **US$15/mês** rodando 24/7 (elegível ao free tier
nos 12 primeiros meses da conta). Para trabalhar com mais dado, mude
`instance_class` em `envs/*.tfvars` — `db.t4g.small` custa ~US$25/mês.

Sem backup automático (`backup_retention_period = 0`) e sem snapshot final:
é um sandbox, e o objetivo é que `terraform destroy` termine sem intervenção
manual.

## Outputs

| Output | Para quê |
|---|---|
| `db_instance_address` | Hostname puro. É o que o DMS e o `psql` esperam. |
| `db_instance_endpoint` | `host:porta`. **Não** serve para o `server_name` do DMS. |
| `db_name`, `db_username`, `db_instance_port` | usados pelo módulo `dms` |

## Destruir

```bash
terraform destroy -var-file=envs/develop.tfvars
```

Se estiver usando Debezium, remova o connector **antes**: um replication slot
órfão prende o WAL e pode encher o disco da instância.
