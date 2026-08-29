#!/bin/bash
# Bootstrap da instância de laboratório: Docker e Docker Compose, nada além.
#
# Roda como user_data no primeiro boot. Amazon Linux 2023 (dnf), e a instância
# é Graviton — por isso nada aqui pode assumir x86.
#
# O log fica em /var/log/user-data.log:
#   aws ssm start-session --target <id>
#   sudo tail -f /var/log/user-data.log
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1
set -xe

dnf update -y
dnf install -y git tar unzip docker

systemctl enable --now docker
usermod -aG docker ec2-user

# O binário do Compose é por arquitetura. `uname -m` devolve aarch64 no
# Graviton e x86_64 numa instância Intel/AMD, e os dois nomes existem no
# release — então isto continua correto se você trocar a família da instância.
COMPOSE_VERSION="v2.24.6"
ARCH="$(uname -m)"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL \
  "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${ARCH}" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Prova que a instalação serve para esta arquitetura: se o binário fosse do
# tipo errado, o exec falharia aqui e não silenciosamente no primeiro uso.
docker compose version

echo "Bootstrap concluído em $(uname -m)."
