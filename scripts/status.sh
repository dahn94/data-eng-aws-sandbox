#!/usr/bin/env bash
# Mostra o que está de pé na AWS agora e o que está custando dinheiro.
#
#   ./scripts/status.sh [develop|main|local]
#
# Pergunta direto para a AWS, não para o state do Terraform — de propósito. O
# state não sabe de um job Glue em execução, e não enxerga um ambiente que você
# aplicou de outra máquina e esqueceu ligado.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

ENVIRONMENT="${1:-develop}"
check_env_arg "$ENVIRONMENT"
SUFFIX="$(env_suffix "$ENVIRONMENT")"

need aws
check_credentials

REGION="${AWS_REGION:-$(aws configure get region || echo us-east-2)}"
TOTAL=0
REDSHIFT_FOUND=0

echo
echo "Ambiente: ${ENVIRONMENT} (sufixo '${SUFFIX}')   Região: ${REGION}"
echo "Conta:    $(aws sts get-caller-identity --query Account --output text)"
echo "─────────────────────────────────────────────────────────────────────"

add_cost() { TOTAL=$((TOTAL + $1)); }

# ---------------------------------------------------------------- RDS
echo
echo "RDS"
rds=$(aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[?starts_with(DBInstanceIdentifier,'${PREFIX}-${SUFFIX}')].[DBInstanceIdentifier,DBInstanceStatus,DBInstanceClass,AllocatedStorage]" \
  --output text 2>/dev/null)
if [[ -z "$rds" ]]; then
  echo "  $(c_dim 'nenhuma instância')"
else
  while read -r id status class storage; do
    [[ -z "$id" ]] && continue
    if [[ "$status" == "available" ]]; then
      echo "  $(c_red '● rodando') $id ($class, ${storage}GB) — ~US\$14/mês"
      echo "    $(c_dim 'pausar mantendo os dados: ./scripts/pause.sh '"$ENVIRONMENT")"
      add_cost 14
    elif [[ "$status" == "stopped" ]]; then
      echo "  $(c_green '○ parada') $id — só o disco (~US\$2/mês)"
      echo "    $(c_dim 'atenção: a AWS religa sozinha depois de 7 dias parada')"
      add_cost 2
    else
      echo "  $(c_yellow "◐ $status") $id"
    fi
  done <<< "$rds"
fi

# ---------------------------------------------------------------- DMS
echo
echo "DMS"
dms=$(aws dms describe-replication-instances --region "$REGION" \
  --query "ReplicationInstances[?starts_with(ReplicationInstanceIdentifier,'dms-instance-${SUFFIX}')].[ReplicationInstanceIdentifier,ReplicationInstanceStatus,ReplicationInstanceClass]" \
  --output text 2>/dev/null)
if [[ -z "$dms" ]]; then
  echo "  $(c_dim 'nenhuma instância')"
else
  while read -r id status class; do
    [[ -z "$id" ]] && continue
    echo "  $(c_red '● rodando') $id ($class) — ~US\$28/mês"
    echo "    $(c_dim 'DMS não tem stop: a única forma de parar de pagar é destruir')"
    add_cost 28
  done <<< "$dms"
fi

# ------------------------------------------- Redshift Serverless
# Modelo de cobrança diferente de todo o resto: não cobra por hora ligado, cobra
# por RPU enquanto processa consulta. O problema é que zero-ETL e materialized
# view com auto refresh fazem o workgroup processar sem ninguém pedir — então
# "ninguém está usando" não quer dizer "não está cobrando".
echo
echo "Redshift Serverless"
RPU_HOUR="0.36"   # us-east-2, por RPU-hora; cobrado por segundo, mínimo de 60s
wgs=$(aws redshift-serverless list-workgroups --region "$REGION" \
  --query "workgroups[?contains(workgroupName,'${PREFIX}-') && contains(workgroupName,'-${SUFFIX}')].[workgroupName,status,baseCapacity]" \
  --output text 2>/dev/null)
if [[ -z "$wgs" ]]; then
  echo "  $(c_dim 'nenhum workgroup')"
else
  while read -r name wstatus rpu; do
    [[ -z "$name" ]] && continue
    hourly=$(awk "BEGIN{printf \"%.2f\", ${rpu:-8} * $RPU_HOUR}")
    echo "  $(c_red '● existe') $name ($wstatus, ${rpu} RPU base)"
    echo "    $(c_dim "~US\$${hourly}/hora ENQUANTO processa — US\$0 parado de verdade")"
    REDSHIFT_FOUND=$((REDSHIFT_FOUND + 1))
  done <<< "$wgs"
  echo "  $(c_yellow 'Redshift Serverless não tem stop.') A única forma de zerar é destruir:"
  echo "  $(c_dim "  ./scripts/teardown.sh $ENVIRONMENT")"
fi

# ---------------------------------------------------------------- EC2
echo
echo "EC2"
ec2=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=DataEngSandbox" "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,InstanceType]" --output text 2>/dev/null)
if [[ -z "$ec2" ]]; then
  echo "  $(c_dim 'nenhuma instância')"
else
  while read -r id state itype; do
    [[ -z "$id" ]] && continue
    if [[ "$state" == "running" ]]; then
      echo "  $(c_red '● rodando') $id ($itype) — ~US\$65/mês"
      add_cost 65
    else
      echo "  $(c_green '○ parada') $id ($itype) — só o disco (~US\$8/mês)"
      add_cost 8
    fi
  done <<< "$ec2"
fi

# ------------------------------------------------------- Glue em execução
# É o que o Terraform não vê: um job de streaming rodando cobra por hora e não
# aparece em nenhum state.
echo
echo "Jobs Glue em execução"
found_run=0
jobs=$(aws glue list-jobs --region "$REGION" --query "JobNames[?ends_with(@,'-${SUFFIX}')]" --output text 2>/dev/null)
for job in $jobs; do
  [[ -z "$job" ]] && continue
  runs=$(aws glue get-job-runs --region "$REGION" --job-name "$job" \
    --query "JobRuns[?JobRunState=='RUNNING'].[Id,ExecutionTime]" --output text 2>/dev/null)
  while read -r runid secs; do
    [[ -z "$runid" ]] && continue
    found_run=1
    echo "  $(c_red '● rodando') $job"
    echo "    run $runid — há $(( ${secs:-0} / 60 )) min"
    echo "    $(c_dim "parar: aws glue batch-stop-job-run --job-name $job --job-run-ids $runid")"
    add_cost 1
  done <<< "$runs"
done
[[ "$found_run" == 0 ]] && echo "  $(c_dim 'nenhum job em execução')"

# ---------------------------------------------------------------- Secrets
echo
echo "Secrets Manager"
secrets=$(aws secretsmanager list-secrets --region "$REGION" \
  --query "SecretList[?starts_with(Name,'${PREFIX}/${SUFFIX}/')].Name" --output text 2>/dev/null)
if [[ -z "$secrets" ]]; then
  echo "  $(c_dim 'nenhum secret')"
else
  n=$(wc -w <<< "$secrets" | tr -d ' ')
  echo "  $n secret(s) — US\$0,40/mês cada"
  add_cost 1
fi

# ---------------------------------------------------------------- S3
echo
echo "S3"
buckets=$(aws s3api list-buckets --query "Buckets[?contains(Name,'lake-')].Name" --output text 2>/dev/null)
if [[ -z "$buckets" ]]; then
  echo "  $(c_dim 'nenhum bucket')"
else
  for b in $buckets; do
    echo "  $b $(c_dim '(cobrança por armazenamento; ciclo de vida de 30 dias nos de dados)')"
  done
fi

# ---------------------------------------------------------------- Total
echo
echo "─────────────────────────────────────────────────────────────────────"
if [[ "$TOTAL" -eq 0 && "$REDSHIFT_FOUND" -eq 0 ]]; then
  echo "  $(c_green 'Nada custando por hora neste ambiente.')"
elif [[ "$TOTAL" -eq 0 ]]; then
  echo "  $(c_yellow 'Nada custando por hora — mas há Redshift Serverless de pé.')"
  echo "  $(c_dim 'Ele cobra por atividade, não por hora, então não entra na conta acima.')"
else
  echo "  Estimativa: ~US\$${TOTAL}/mês se ficar tudo assim por 30 dias."
  echo "  $(c_dim 'Números aproximados de us-east-2 on-demand. O valor real está no')"
  echo "  $(c_dim 'Cost Explorer — este script serve para você lembrar do que ligou.')"
  echo
  if [[ "$REDSHIFT_FOUND" -gt 0 ]]; then
    echo "  $(c_yellow 'A estimativa NÃO inclui o Redshift Serverless') — ele cobra por"
    echo "  $(c_dim 'atividade. Com zero-ETL ou auto refresh ligados, essa atividade é')"
    echo "  $(c_dim 'contínua, e o teto de 4 RPU processando 24/7 passa de US$1.000/mês.')"
    echo
  fi
  echo "  Pausar (mantém os dados):  ./scripts/pause.sh $ENVIRONMENT"
  echo "  Destruir tudo:             ./scripts/teardown.sh $ENVIRONMENT"
fi
echo
