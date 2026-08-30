# bi-metabase

Metabase local, usado pra dashboards de BI sobre os dados processados.

## Subir

```bash
cd platform/local/services/bi-metabase
docker compose up -d
```

Acesso: http://localhost:3000 (primeira execução pede setup inicial).

## Conteúdo

- `docker-compose.yml` — Metabase + Postgres interno de metadados.
- `dashboards.sql` — queries de referência usadas nos dashboards.
