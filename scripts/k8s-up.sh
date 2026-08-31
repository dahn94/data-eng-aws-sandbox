#!/usr/bin/env bash
# Cria o cluster Kubernetes local a partir de platform/local/cluster/kind.yaml.
#
# Idempotente: se o cluster já existe, não recria.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO_ROOT/platform/local/cluster/kind.yaml"
CLUSTER=dataeng

for bin in kind helm kubectl; do
  command -v "$bin" >/dev/null || { echo "falta $bin — brew install $bin"; exit 1; }
done

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "cluster '$CLUSTER' já existe"
else
  # envsubst não vem no macOS por padrão: o sed faz o mesmo para uma variável.
  sed "s#\${REPO_ROOT}#$REPO_ROOT#g" "$CONFIG" | kind create cluster --config -
fi

# Fixa o contexto: o OrbStack sobe um Kubernetes próprio e o toma como
# corrente, e um `helm install` distraído vai para o cluster errado sem avisar.
kubectl config use-context "kind-$CLUSTER"
kubectl cluster-info --context "kind-$CLUSTER"
echo
echo "As imagens construídas nesta máquina precisam ser carregadas no cluster:"
echo "  ./scripts/k8s-images.sh"
