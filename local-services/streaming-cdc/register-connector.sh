#!/usr/bin/env bash
# Registra o connector Debezium no Kafka Connect.
#
# O nome do tópico gerado é <topic.prefix>.<schema>.<tabela>, ou seja
# `ecommerce.public.web_events` — é esse valor que o job Glue de streaming e o
# DDL do ClickHouse esperam. Se mudar o topic.prefix aqui, mude nos dois.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -f .env ]]; then
  echo "erro: .env não existe. Rode: cp .env.example .env e edite." >&2
  exit 1
fi

set -a; source .env; set +a

: "${POSTGRES_HOST:?defina POSTGRES_HOST no .env}"
: "${POSTGRES_PASSWORD:?defina POSTGRES_PASSWORD no .env}"

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

# A senha vai para um arquivo de propriedades lido pelo Connect em runtime, em
# vez de ficar embutida no JSON que fica versionado.
docker compose exec -T connect sh -c "cat > /kafka/config/connector-secrets.properties" <<PROPS
postgres_host=${POSTGRES_HOST}
postgres_user=${POSTGRES_USER:-postgres}
postgres_password=${POSTGRES_PASSWORD}
postgres_db=${POSTGRES_DB:-dataengsandbox}
PROPS

echo "==> registrando connector em ${CONNECT_URL}"
curl -fsS -X PUT \
  -H "Content-Type: application/json" \
  --data @register-postgres-connector.json \
  "${CONNECT_URL}/connectors/postgres-connector/config" | python3 -m json.tool

echo
echo "==> status"
sleep 3
curl -fsS "${CONNECT_URL}/connectors/postgres-connector/status" | python3 -m json.tool
