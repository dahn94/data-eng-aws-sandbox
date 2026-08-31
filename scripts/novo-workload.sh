#!/usr/bin/env bash
# Cria um workload novo no padrão do repositório.
#
#   ./scripts/novo-workload.sh <nome> [--local]
#
# Faz o que a seção "Roadmap" do README descreve em prosa: a pasta com os
# quatro .tf, envs/, backends/, README.md, nfr.md e adr/, mais a ÚNICA coisa
# que mora fora dela — o workflow de CI. Com --local, cria também a forma
# local em Docker.
#
# Nada aqui é obrigatório: é um ponto de partida no formato certo, para que o
# trabalho comece no problema e não na estrutura. Depois de gerar, rode
# ./scripts/verifica.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPO_ROOT/scripts/template-workload"

NOME="${1:-}"
COM_LOCAL="${2:-}"

if [ -z "$NOME" ]; then
  echo "uso: $0 <nome> [--local]" >&2
  exit 1
fi

if ! printf '%s' "$NOME" | grep -qE '^[a-z][a-z0-9-]*$'; then
  echo "nome inválido: '$NOME' — use minúsculas, dígitos e hífen (ex.: zero-etl)" >&2
  exit 1
fi

DESTINO="$REPO_ROOT/workloads/$NOME"
WORKFLOW="$REPO_ROOT/.github/workflows/workload-$NOME-ci.yml"

[ -e "$DESTINO" ] && { echo "já existe: workloads/$NOME" >&2; exit 1; }
[ -e "$WORKFLOW" ] && { echo "já existe: $(basename "$WORKFLOW")" >&2; exit 1; }

# Copia a árvore trocando {{NOME}} e tirando o sufixo .tmpl.
copia() {  # copia <origem> <destino>
  mkdir -p "$(dirname "$2")"
  sed "s/{{NOME}}/$NOME/g" "$1" > "$2"
}

while IFS= read -r origem; do
  relativo="${origem#"$TEMPLATE"/}"
  case "$relativo" in
    local/*)  [ "$COM_LOCAL" = "--local" ] || continue ;;
    ci.yml.tmpl) continue ;;   # vai para .github/workflows, não para dentro do workload
  esac
  copia "$origem" "$DESTINO/${relativo%.tmpl}"
done < <(find "$TEMPLATE" -type f -name '*.tmpl')

# O adr/ precisa existir desde o começo: é onde a primeira decisão vai morar,
# e o verifica.sh cobra a pasta.
mkdir -p "$DESTINO/aws/adr"
cp "$TEMPLATE/aws/adr/.gitkeep" "$DESTINO/aws/adr/.gitkeep"

copia "$TEMPLATE/ci.yml.tmpl" "$WORKFLOW"

echo "criado workloads/$NOME:"
(cd "$REPO_ROOT" && find "workloads/$NOME" -type f | sort | sed 's/^/  /')
echo "  .github/workflows/workload-$NOME-ci.yml"
cat <<FIM

Próximos passos, na ordem em que o repositório espera:
  1. workloads/$NOME/README.md   — enuncie o PROBLEMA (não a ferramenta)
  2. workloads/$NOME/aws/nfr.md  — troque os "não declarado" pelo que você exige
  3. aws/infra/main.tf           — os recursos, instanciando platform/aws/modules
  4. ao usar um módulo, some o path dele aos filtros do workflow de CI
  5. ./scripts/verifica.sh
FIM
