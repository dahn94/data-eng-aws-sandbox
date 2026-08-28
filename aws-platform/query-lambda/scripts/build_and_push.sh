#!/usr/bin/env bash
# Constrói e publica a imagem da Lambda no ECR.
#
# O repositório ECR é criado pelo Terraform (aws-platform/query-lambda), não
# por este script. Ordem:
#   1. terraform apply  -> cria o repositório ECR
#   2. ./build_and_push.sh
#   3. terraform apply -var="image_tag=<tag impressa no fim>"
#
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-2}"
ECR_REPOSITORY="${ECR_REPOSITORY:-lambda-duckdb-sandbox}"

# Tag imutável derivada do conteúdo: com :latest o Terraform nunca percebe que
# a imagem mudou e a Lambda continua servindo o código antigo.
IMAGE_TAG="${IMAGE_TAG:-$(cat Dockerfile requirements.txt lambda_handler.py | shasum -a 256 | cut -c1-12)}"

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "erro: repositório ECR '$ECR_REPOSITORY' não existe." >&2
  echo "      rode primeiro: cd .. && terraform apply -var-file=envs/develop.tfvars" >&2
  exit 1
fi

if aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids "imageTag=$IMAGE_TAG" \
     --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Imagem ${IMAGE_TAG} já publicada — nada a fazer."
  echo "IMAGE_TAG=${IMAGE_TAG}"
  exit 0
fi

echo "==> login no ECR"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_URI"

echo "==> build (${IMAGE_TAG})"
# A Lambda roda em x86_64; sem --platform, um Mac ARM produz uma imagem que a
# função não consegue executar.
docker build --platform linux/amd64 -t "${ECR_URI}:${IMAGE_TAG}" -f Dockerfile .

echo "==> push"
docker push "${ECR_URI}:${IMAGE_TAG}"

echo
echo "Pronto. Aplique a função com:"
echo "  cd .. && terraform apply -var-file=envs/develop.tfvars -var=\"image_tag=${IMAGE_TAG}\""
echo "IMAGE_TAG=${IMAGE_TAG}"
