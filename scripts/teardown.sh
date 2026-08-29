#!/usr/bin/env bash
# Destrói tudo de um ambiente, na ordem certa.
#
#   ./scripts/teardown.sh [develop|main|local] [--dry-run] [--yes]
#
# A ordem importa: módulos dependem do state uns dos outros, e o `foundation`
# guarda o state de todos — ele vai por último. Rodar terraform destroy na
# ordem errada deixa recurso órfão que você só descobre na fatura.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

ENVIRONMENT="develop"
DRY_RUN=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *)         ENVIRONMENT="$arg" ;;
  esac
done

check_env_arg "$ENVIRONMENT"
need terraform

# Ordem inversa da de aplicação: workloads primeiro, plataforma depois, e o
# foundation — que guarda os states — por último.
#
# federated-query e zero-etl penduram recurso NO rds (regra de security group,
# integração zero-ETL). Se o rds for destruído antes, o destroy deles falha ou
# deixa órfão. Por isso vêm antes, e não junto dos outros workloads.
DESTROY_ORDER=(
  "workloads/data-sharing"
  "workloads/incremental-mv"
  "workloads/zero-etl"
  "workloads/federated-query"
  "workloads/webevents-streaming"
  "workloads/amazonsales"
  "workloads/query-lambda"
  "workloads/dms"
  "platform/ec2"
  "platform/rds"
  "platform/network"
  "platform/foundation"
)

echo
echo "Ambiente a destruir: $(c_red "$ENVIRONMENT")"
echo
echo "Ordem:"
SKIPPED=0
PLANNED=0
for m in "${DESTROY_ORDER[@]}"; do
  if has_state "$m" "$ENVIRONMENT"; then
    echo "  $(c_yellow '→') $m"
    PLANNED=$((PLANNED + 1))
  else
    echo "  $(c_dim "· $m (sem state local, será pulado)")"
    SKIPPED=$((SKIPPED + 1))
  fi
done

# "Sem state local" significa apenas que este diretório nunca passou por um
# `terraform init` NESTA máquina — não que não haja nada aplicado na AWS. Quem
# aplicou de outro computador ou de um runner de CI cairia aqui e leria um
# "tudo destruído" que não é verdade.
if [[ "$SKIPPED" -gt 0 ]]; then
  echo
  echo "$(c_yellow 'Atenção:') $SKIPPED módulo(s) sem \`.terraform\` local serão pulados."
  echo "Isso NÃO garante que não exista nada aplicado na AWS — só que esta"
  echo "máquina nunca inicializou esses módulos. Se você aplicou de outro lugar,"
  echo "rode primeiro, em cada um deles:"
  echo "  $(c_dim "terraform init -backend-config=backends/${ENVIRONMENT}.hcl")"
  echo "Ou confira o que existe de verdade com: $(c_dim "./scripts/status.sh $ENVIRONMENT")"
fi

if [[ "$PLANNED" -eq 0 && "$DRY_RUN" != 1 ]]; then
  echo
  echo "Nada a destruir nesta máquina. Nada foi feito."
  exit 0
fi

if [[ "$DRY_RUN" == 1 ]]; then
  echo
  echo "$(c_dim '--dry-run: nada foi executado.')"
  exit 0
fi

echo
echo "$(c_red 'Isto apaga os recursos e os dados deste ambiente, sem volta.')"
echo "Os buckets têm force_destroy = true: objetos dentro vão junto."
if [[ "$ASSUME_YES" != 1 ]]; then
  printf "Digite o nome do ambiente para confirmar: "
  read -r answer
  [[ "$answer" == "$ENVIRONMENT" ]] || die "confirmação não confere. Nada foi feito."
fi

# ---------------------------------------------------------------------------
# Antes do terraform: parar jobs Glue em execução.
# Um job de streaming ativo não aparece em nenhum state, e destruir a definição
# do job com um run vivo deixa a execução — e a cobrança — em aberto.
# ---------------------------------------------------------------------------
if command -v aws >/dev/null 2>&1 && aws sts get-caller-identity >/dev/null 2>&1; then
  SUFFIX="$(env_suffix "$ENVIRONMENT")"
  REGION="${AWS_REGION:-$(aws configure get region || echo us-east-2)}"
  echo
  echo "Parando jobs Glue em execução..."
  jobs=$(aws glue list-jobs --region "$REGION" --query "JobNames[?ends_with(@,'-${SUFFIX}')]" --output text 2>/dev/null)
  for job in $jobs; do
    [[ -z "$job" ]] && continue
    runs=$(aws glue get-job-runs --region "$REGION" --job-name "$job" \
      --query "JobRuns[?JobRunState=='RUNNING'].Id" --output text 2>/dev/null)
    for runid in $runs; do
      [[ -z "$runid" ]] && continue
      echo "  $job (run $runid)"
      aws glue batch-stop-job-run --region "$REGION" --job-name "$job" --job-run-ids "$runid" >/dev/null 2>&1 || true
    done
  done
fi

# ---------------------------------------------------------------------------
FAILED=()
for m in "${DESTROY_ORDER[@]}"; do
  has_state "$m" "$ENVIRONMENT" || continue

  echo
  echo "══ $m ══"
  (
    cd "$REPO_ROOT/$m" || exit 1
    # O foundation usa state local e não tem backend remoto para configurar.
    if [[ "$m" != *"/foundation" ]]; then
      terraform init -reconfigure -input=false \
        -backend-config="backends/${ENVIRONMENT}.hcl" >/dev/null || exit 1
    fi
    # As senhas não importam para destruir, mas o Terraform exige um valor
    # para variáveis sem default antes de montar o plano.
    TF_VAR_rds_password="${TF_VAR_rds_password:-unused-for-destroy}" \
    TF_VAR_opensearch_password="${TF_VAR_opensearch_password:-unused-for-destroy}" \
      terraform destroy -auto-approve -input=false -lock-timeout=5m \
        -var-file="envs/${ENVIRONMENT}.tfvars"
  ) || FAILED+=("$m")
done

echo
echo "─────────────────────────────────────────────────────────────────────"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  if [[ "$SKIPPED" -gt 0 ]]; then
    echo "  $(c_green "Destruídos os $PLANNED módulo(s) inicializados nesta máquina.")"
    echo "  $(c_yellow "$SKIPPED foram pulados") — confirme com status.sh que não sobrou nada."
  else
    echo "  $(c_green 'Tudo destruído.')"
  fi
else
  echo "  $(c_red 'Falharam:')"
  for m in "${FAILED[@]}"; do echo "    - $m"; done
  echo
  echo "  Recurso órfão continua cobrando. Rode o script de novo, ou olhe o"
  echo "  console. Causa comum: bucket com objeto novo criado depois do plano."
fi
echo
echo "  Confira o que sobrou: ./scripts/status.sh $ENVIRONMENT"
echo
