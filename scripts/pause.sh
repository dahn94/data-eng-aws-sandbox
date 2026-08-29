#!/usr/bin/env bash
# Para o que dá para parar, sem destruir nada.
#
#   ./scripts/pause.sh [develop|main|local]
#
# Use entre sessões de estudo: seus dados e sua infraestrutura continuam lá, e
# você para de pagar pela parte cara. Para retomar: ./scripts/resume.sh
#
# O que NÃO dá para pausar: a instância de replicação do DMS e os workgroups do
# Redshift Serverless. Nenhum dos dois tem stop — a única forma de parar de
# pagar é destruir (teardown.sh).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

ENVIRONMENT="${1:-develop}"
check_env_arg "$ENVIRONMENT"
SUFFIX="$(env_suffix "$ENVIRONMENT")"

need aws
check_credentials
REGION="${AWS_REGION:-$(aws configure get region || echo us-east-2)}"

echo "Pausando o ambiente '${ENVIRONMENT}' em ${REGION}..."
echo

# ------------------------------------------------ 1. jobs Glue em execução
# Primeiro, porque um job de streaming continua cobrando mesmo com o banco
# parado — e ele falharia sozinho de qualquer forma sem a origem.
echo "Jobs Glue"
stopped_any=0
jobs=$(aws glue list-jobs --region "$REGION" --query "JobNames[?ends_with(@,'-${SUFFIX}')]" --output text 2>/dev/null)
for job in $jobs; do
  [[ -z "$job" ]] && continue
  runs=$(aws glue get-job-runs --region "$REGION" --job-name "$job" \
    --query "JobRuns[?JobRunState=='RUNNING'].Id" --output text 2>/dev/null)
  for runid in $runs; do
    [[ -z "$runid" ]] && continue
    echo "  parando $job (run $runid)"
    aws glue batch-stop-job-run --region "$REGION" --job-name "$job" --job-run-ids "$runid" >/dev/null \
      && stopped_any=1 || echo "  $(c_yellow 'aviso') falha ao parar $job"
  done
done
[[ "$stopped_any" == 0 ]] && echo "  $(c_dim 'nenhum job em execução')"

# ------------------------------------------------ 2. RDS
echo
echo "RDS"
rds=$(aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[?starts_with(DBInstanceIdentifier,'${PREFIX}-${SUFFIX}') && DBInstanceStatus=='available'].DBInstanceIdentifier" \
  --output text 2>/dev/null)
if [[ -z "$rds" ]]; then
  echo "  $(c_dim 'nada rodando')"
else
  for id in $rds; do
    echo "  parando $id"
    aws rds stop-db-instance --region "$REGION" --db-instance-identifier "$id" >/dev/null \
      && echo "  $(c_green 'ok')" || echo "  $(c_yellow 'aviso') falha ao parar $id"
  done
  echo "  $(c_yellow 'atenção:') a AWS religa uma instância parada automaticamente"
  echo "  após 7 dias. Para uma pausa mais longa, use teardown.sh."
fi

# ------------------------------------------------ 3. EC2 (não dá para pausar)
# A instância de laboratório é spot com requisição one-time: a AWS não oferece
# stop para ela. Aqui só avisamos; parar de pagar exige destruir.
echo
echo "EC2 (laboratório)"
ec2=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=DataEngSandbox" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[InstanceId,InstanceLifecycle]" --output text 2>/dev/null)
if [[ -z "$ec2" ]]; then
  echo "  $(c_dim 'nada rodando')"
else
  while read -r id lifecycle; do
    [[ -z "$id" ]] && continue
    if [[ "$lifecycle" == "spot" ]]; then
      echo "  $(c_yellow 'não pausável') $id — spot one-time não tem stop"
    else
      echo "  parando $id"
      aws ec2 stop-instances --region "$REGION" --instance-ids "$id" >/dev/null \
        && echo "  $(c_green 'ok')" || echo "  $(c_yellow 'aviso') falha ao parar $id"
    fi
  done <<< "$ec2"
fi

# ------------------------------------------------ 4. o que sobra
echo
dms=$(aws dms describe-replication-instances --region "$REGION" \
  --query "ReplicationInstances[?starts_with(ReplicationInstanceIdentifier,'dms-instance-${SUFFIX}')].ReplicationInstanceIdentifier" \
  --output text 2>/dev/null)
if [[ -n "$dms" ]]; then
  echo "$(c_red 'AINDA COBRANDO:') instância DMS $dms (~US\$28/mês)"
  echo "O DMS não tem stop. Para parar de pagar:"
  echo "  cd workloads/dms && terraform destroy -var-file=envs/${ENVIRONMENT}.tfvars"
  echo
fi

# Redshift Serverless: mesmo problema do DMS, com um agravante. Ele não cobra
# por hora ligado, cobra por RPU enquanto processa — só que zero-ETL e
# materialized view com auto refresh o fazem processar sem ninguém pedir. Pausar
# o RDS não interrompe isso.
wgs=$(aws redshift-serverless list-workgroups --region "$REGION" \
  --query "workgroups[?contains(workgroupName,'${PREFIX}-') && contains(workgroupName,'-${SUFFIX}')].workgroupName" \
  --output text 2>/dev/null)
if [[ -n "$wgs" ]]; then
  echo "$(c_red 'AINDA COBRANDO:') workgroup(s) Redshift Serverless"
  for wg in $wgs; do echo "  $wg"; done
  echo "Redshift Serverless não tem stop, e com zero-ETL ou auto refresh ele"
  echo "processa sozinho. Para parar de pagar, destrua o workload:"
  echo "  cd workloads/<zero-etl|incremental-mv|data-sharing> \\"
  echo "    && terraform destroy -var-file=envs/${ENVIRONMENT}.tfvars"
  echo
fi

echo "Pronto. Confira com: ./scripts/status.sh $ENVIRONMENT"
echo "Retomar com:         ./scripts/resume.sh $ENVIRONMENT"
