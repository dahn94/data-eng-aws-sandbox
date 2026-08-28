#!/usr/bin/env bash
# Troca o placeholder CHANGEME pelo seu prefixo de bucket em todos os arquivos
# que precisam dele (backends/*.hcl, envs/*.tfvars).
#
# Nomes de bucket S3 são globais na AWS inteira, então cada pessoa que clona
# este repositório precisa do seu próprio prefixo. Rode isto uma vez, logo
# depois do clone:
#
#   ./scripts/set-bucket-prefix.sh meu-usuario
#
set -euo pipefail

PREFIX="${1:-}"

if [[ -z "$PREFIX" ]]; then
  echo "uso: $0 <prefixo>    (ex: $0 meu-usuario)" >&2
  exit 1
fi

if ! [[ "$PREFIX" =~ ^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$ ]]; then
  echo "erro: prefixo inválido '$PREFIX'." >&2
  echo "      use 3-32 caracteres, só minúsculas, números e hífens." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FILES=$(grep -rl 'CHANGEME' --include='*.hcl' --include='*.tfvars' . || true)

if [[ -z "$FILES" ]]; then
  echo "Nenhum CHANGEME encontrado — o prefixo já foi definido."
  echo "Para trocar de novo, edite os arquivos manualmente ou use git checkout."
  exit 0
fi

echo "$FILES" | while read -r f; do
  # -i '' é a sintaxe do sed do macOS; -i'' funciona nos dois com o backup vazio.
  perl -pi -e "s/CHANGEME/${PREFIX}/g" "$f"
  echo "  atualizado: $f"
done

echo
echo "Pronto. Prefixo definido como '${PREFIX}'."
echo "Seus buckets serão:"
echo "  ${PREFIX}-lake-configs          (tfstate, scripts, jars)"
echo "  ${PREFIX}-lake-raw-<ambiente>"
echo "  ${PREFIX}-lake-curated-<ambiente>"
echo "  ${PREFIX}-lake-logs-<ambiente>"
echo
echo "Próximo passo: cd aws-platform/foundation && terraform init && \\"
echo "  terraform apply -var-file=envs/develop.tfvars"
