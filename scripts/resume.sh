#!/usr/bin/env bash
# Religa o que o pause.sh parou.
#
#   ./scripts/resume.sh [develop|main|local]
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

ENVIRONMENT="${1:-develop}"
check_env_arg "$ENVIRONMENT"
SUFFIX="$(env_suffix "$ENVIRONMENT")"

need aws
check_credentials
REGION="${AWS_REGION:-$(aws configure get region || echo us-east-2)}"

echo "Retomando o ambiente '${ENVIRONMENT}' em ${REGION}..."
echo

echo "RDS"
rds=$(aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[?starts_with(DBInstanceIdentifier,'${PREFIX}-${SUFFIX}') && DBInstanceStatus=='stopped'].DBInstanceIdentifier" \
  --output text 2>/dev/null)
if [[ -z "$rds" ]]; then
  echo "  $(c_dim 'nada parado')"
else
  for id in $rds; do
    echo "  iniciando $id"
    aws rds start-db-instance --region "$REGION" --db-instance-identifier "$id" >/dev/null \
      && echo "  $(c_green 'ok') (leva alguns minutos até ficar available)"
  done
fi

echo
echo "EC2"
ec2=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=DataEngSandbox" "Name=instance-state-name,Values=stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null)
if [[ -z "$ec2" ]]; then
  echo "  $(c_dim 'nada parado')"
else
  echo "  iniciando: $ec2"
  # shellcheck disable=SC2086
  aws ec2 start-instances --region "$REGION" --instance-ids $ec2 >/dev/null && echo "  $(c_green 'ok')"
  echo "  $(c_yellow 'atenção:') o IP público muda a cada start. Se você usa a EC2"
  echo "  como streaming_host, atualize o valor antes de rodar o job."
fi

echo
echo "Os jobs Glue não são reiniciados automaticamente — dispare o que precisar."
echo "Confira com: ./scripts/status.sh $ENVIRONMENT"
