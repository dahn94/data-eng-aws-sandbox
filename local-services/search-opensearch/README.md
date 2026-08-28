# search-opensearch

OpenSearch + OpenSearch Dashboards em Docker, destino do job de streaming de
eventos web.

## Subir

```bash
cd local-services/search-opensearch
cp .env.example .env
$EDITOR .env    # defina OPENSEARCH_INITIAL_ADMIN_PASSWORD

docker compose up -d
```

A senha precisa ser forte (8+ caracteres, maiúscula, minúscula, número e
símbolo) — com senha fraca o container sobe e morre em seguida.

- OpenSearch: https://localhost:9200 (usuário `admin`, certificado autoassinado)
- Dashboards: http://localhost:5601

## Ligação com a AWS

A mesma senha vai para o job Glue de streaming, mas por outro caminho: você a
passa como `TF_VAR_opensearch_password` em
`aws-platform/pipelines/webevents-streaming`, e o Terraform a grava num secret
do Secrets Manager. O job lê o secret em runtime — a senha nunca aparece como
argumento do job.

## Encerrar

```bash
docker compose down -v
```
