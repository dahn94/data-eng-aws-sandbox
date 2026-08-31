#!/usr/bin/env bash
# Constrói (se faltar) e carrega no cluster as imagens que só existem nesta
# máquina.
#
# Os nós do kind não enxergam o daemon Docker do host: uma imagem que só existe
# aqui precisa ser empurrada para dentro do nó, senão o pod fica em
# ErrImagePull sem explicação óbvia.
#
# Os Dockerfiles ainda moram em platform/local/services/ — enquanto o Compose
# existir, ele e os charts constroem A MESMA imagem. Quando o Compose sair, os
# Dockerfiles vão junto para platform/local/modules/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER=dataeng

# imagem<TAB>contexto de build
IMAGENS=$(cat <<MAP
dataeng-sandbox/glue:5.0.10-gx	$REPO_ROOT/platform/local/services/spark-glue
dataeng-sandbox/spark-oss:3.5.7-gx	$REPO_ROOT/platform/local/services/spark-oss
dataeng-sandbox/iceberg-rest:1.9.2-pg	$REPO_ROOT/platform/local/services/iceberg-catalog
dataeng-sandbox/superset:latest	$REPO_ROOT/platform/local/services/bi-superset
dataeng-sandbox/airflow:3.1.3-k8s	$REPO_ROOT/platform/local/modules/orchestration-airflow
MAP
)

while IFS=$'\t' read -r img contexto; do
  [ -z "$img" ] && continue
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    echo "construindo $img"
    docker build -t "$img" "$contexto"
  fi
  echo "carregando $img"
  kind load docker-image --name "$CLUSTER" "$img"
done <<< "$IMAGENS"

echo "pronto"
