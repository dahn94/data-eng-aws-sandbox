# data-generator

Script Python que gera eventos web sintéticos continuamente e insere na tabela
`web_events` do Postgres — é a origem dos dados que o CDC (DMS ou Debezium)
captura.

## Rodar

```bash
cd local-services/data-generator
pip install -r requirements.txt

export PGHOST=<endpoint-do-rds>     # terraform output -raw db_instance_address
export PGPASSWORD=<senha-do-postgres>
# opcionais:
export PGUSER=postgres
export PGPORT=5432
export PGDATABASE=dataengsandbox    # casa com o db_name criado por modules/rds
export BATCH_INTERVAL_SECONDS=60

python3 script-insert-postgres-webfake-events.py
```

Grava um lote a cada 60 segundos. Encerre com Ctrl+C — o script termina o lote
atual e sai limpo.

## REPLICA IDENTITY

Depois do primeiro lote, o script roda
`ALTER TABLE web_events REPLICA IDENTITY FULL`. Sem isso, o CDC entrega apenas
a chave primária no campo `before` de updates e deletes, e a transformação do
job de streaming — que lê `before` em deletes — receberia quase tudo nulo.

## Pré-requisito

O `PGHOST` precisa estar alcançável da sua máquina. No RDS deste repositório
isso significa colocar seu IP em `allowed_cidr_blocks` no
`workloads/<workload>/envs/develop.tfvars` do workload cuja fonte você está usando.
