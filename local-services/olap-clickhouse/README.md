# olap-clickhouse

Stack local do ClickHouse, usado como motor OLAP alternativo pra consultar
os dados que caem no data lake.

## Subir

```bash
cd local-services/olap-clickhouse
docker compose up -d
```

## Conteúdo

- `docker-compose.yml` — sobe o ClickHouse Server.
- `create-table-events.sql` — DDL de exemplo pra criar a tabela de eventos.
