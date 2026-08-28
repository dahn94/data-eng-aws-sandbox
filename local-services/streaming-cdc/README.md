# streaming-cdc

Stack local de Kafka + Debezium + Schema Registry, para capturar mudanças (CDC)
do Postgres em tempo real via replicação lógica — alternativa ao DMS.

## Subir

O `.env` é **obrigatório**: as imagens usam `${DEBEZIUM_VERSION}` e o listener
externo usa `${EC2_IP}`. Sem ele o compose sobe com tags de imagem vazias e
falha.

```bash
cd local-services/streaming-cdc
cp .env.example .env
$EDITOR .env          # POSTGRES_HOST, POSTGRES_PASSWORD, EC2_IP

../../scripts/fetch-jars.sh   # jars do Avro/Schema Registry (uma vez só)

docker compose up -d
```

Espere os healthchecks ficarem verdes (`docker compose ps`) e registre o
connector:

```bash
./register-connector.sh
```

## Pré-requisito no Postgres

A origem precisa de `rds.logical_replication = 1`. O módulo
`aws-platform/rds` já configura isso; se você estiver usando um Postgres
próprio, garanta `wal_level = logical`. Sem isso o connector faz o snapshot
inicial e depois fica parado para sempre, sem erro claro.

## O nome do tópico importa

O connector usa `topic.prefix = ecommerce`, então o tópico gerado é
**`ecommerce.public.web_events`**. Esse nome aparece em outros dois lugares:

- `aws-platform/pipelines/webevents-streaming` (variável `kafka_topic`)
- `local-services/olap-clickhouse/create-table-events.sql`

Se mudar o prefixo aqui, mude nos dois.

## Conteúdo

| Arquivo | O que é |
|---|---|
| `docker-compose.yml` | Zookeeper, Kafka, Schema Registry, Kafka Connect, Kafka UI (porta 8080) |
| `.env.example` | Modelo de variáveis. Copie para `.env`, que é ignorado pelo Git |
| `register-postgres-connector.json` | Configuração do connector Debezium |
| `register-connector.sh` | Registra o connector e mostra o status |
| `jars/debezium/` | Jars do Avro/Schema Registry. Baixados por `scripts/fetch-jars.sh`, montados como plugin do Connect |

A senha do Postgres não fica no JSON versionado: o `register-connector.sh`
escreve um arquivo de propriedades dentro do container e o JSON referencia
`${file:...}`.

## Encerrar

```bash
docker compose down -v
```

**Antes de destruir o RDS**, remova o connector — um replication slot órfão
prende o WAL e enche o disco da instância:

```bash
curl -X DELETE http://localhost:8083/connectors/postgres-connector
```
