#!/usr/bin/env bash
# Falha quando o repositório passa a mentir.
#
#   ./scripts/verifica.sh
#
# Existe porque a documentação daqui cita arquivo e linha, e os filtros de path
# da CI citam módulos: as duas coisas apodrecem em silêncio quando algo é
# movido. Rode depois de qualquer refatoração — é mais barato que descobrir
# meses depois lendo o README.
#
# A CI deste repo está desligada de propósito, então isto é para rodar na mão
# (ou de um hook de pre-commit seu, se quiser).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROBLEMAS=0
erro() { echo "  ✗ $*"; PROBLEMAS=$((PROBLEMAS + 1)); }
secao() { echo; echo "$*"; }

# ---------------------------------------------------------------------------
secao "1. estrutura dos workloads"
# ---------------------------------------------------------------------------
for main in workloads/*/aws/infra/main.tf; do
  [ -e "$main" ] || continue
  w=$(basename "$(dirname "$(dirname "$(dirname "$main")")")")
  for exigido in \
    "workloads/$w/README.md" \
    "workloads/$w/aws/infra/variables.tf" \
    "workloads/$w/aws/infra/outputs.tf" \
    "workloads/$w/aws/infra/versions.tf" \
    "workloads/$w/aws/infra/envs" \
    "workloads/$w/aws/infra/backends" \
    "workloads/$w/aws/nfr.md" \
    "workloads/$w/aws/adr"
  do
    [ -e "$exigido" ] || erro "$w: falta $exigido"
  done
done
echo "  ($(ls -d workloads/*/aws/infra 2>/dev/null | wc -l | tr -d ' ') workloads)"

# ---------------------------------------------------------------------------
secao "2. filtros de path da CI vs. módulos usados"
# ---------------------------------------------------------------------------
for main in workloads/*/aws/infra/main.tf; do
  [ -e "$main" ] || continue
  w=$(basename "$(dirname "$(dirname "$(dirname "$main")")")")
  wf=".github/workflows/workload-$w-ci.yml"
  if [ ! -e "$wf" ]; then
    erro "$w: sem workflow de CI ($wf)"
    continue
  fi
  usados=$(grep -ho 'platform/aws/modules/[a-z0-9_-]*' workloads/"$w"/aws/infra/*.tf 2>/dev/null | sed 's|.*modules/||' | sort -u)
  filtrados=$(grep -o 'platform/aws/modules/[a-z0-9_-]*' "$wf" 2>/dev/null | sed 's|.*modules/||' | sort -u)
  faltando=$(comm -23 <(echo "$usados") <(echo "$filtrados") | tr '\n' ' ')
  [ -n "${faltando// /}" ] && erro "$w: usa mas a CI não filtra -> ${faltando% }"
done

# ---------------------------------------------------------------------------
secao "3. citações e links na documentação"
# ---------------------------------------------------------------------------
python3 - <<'PY'
import os, re, glob, sys

problemas = []
citacoes = links = 0

def existe(base, alvo):
    return any(os.path.exists(p) for p in (os.path.join(base, alvo), alvo))

for md in glob.glob('**/*.md', recursive=True):
    if md.startswith('.git') or md.startswith('scripts/template-workload'):
        continue
    base = os.path.dirname(md)
    texto = open(md, encoding='utf-8').read()

    # `caminho/arquivo.ext:123` — a citação que aponta para o código
    for m in re.finditer(r'`([\w./-]+\.(?:tf|py|sh|yml|yaml|json|md|sql|hcl|tfvars))(?::(\d+)(?:-\d+)?)?`', texto):
        caminho, linha = m.group(1), m.group(2)
        if not linha:
            continue
        citacoes += 1
        if not existe(base, caminho):
            problemas.append(f"{md}: cita {m.group(0)} — arquivo não existe")

    # [texto](caminho relativo)
    for m in re.finditer(r'\]\(([^)\s]+)\)', texto):
        alvo = m.group(1)
        if alvo.startswith(('http', 'mailto:', '#')):
            continue
        links += 1
        limpo = alvo.split('#')[0]
        if limpo and not existe(base, limpo):
            problemas.append(f"{md}: link quebrado -> {alvo}")

print(f"  ({citacoes} citações com linha, {links} links relativos)")
for p in problemas:
    print(f"  ✗ {p}")
sys.exit(1 if problemas else 0)
PY
[ $? -ne 0 ] && PROBLEMAS=$((PROBLEMAS + 1))

# ---------------------------------------------------------------------------
secao "4. os docker-compose renderizam"
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  for compose in workloads/*/local/infra/docker-compose.yml; do
    [ -e "$compose" ] || continue
    (cd "$(dirname "$compose")" && docker compose config -q >/dev/null 2>&1) \
      || erro "$compose não renderiza (docker compose config)"
  done
  echo "  ($(ls workloads/*/local/infra/docker-compose.yml 2>/dev/null | wc -l | tr -d ' ') workloads com forma local)"
else
  echo "  (docker não encontrado — pulado)"
fi

# ---------------------------------------------------------------------------
echo
if [ "$PROBLEMAS" -eq 0 ]; then
  echo "tudo consistente."
else
  echo "$PROBLEMAS verificação(ões) com problema."
fi
exit $((PROBLEMAS > 0))
