#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data ) 2>&1
set -xe

# Atualiza sistema
dnf update -y

# Instala dependências
dnf install -y \
    git \
    unzip \
    wget \
    tar \
    java-17-amazon-corretto \
    docker

# Habilita Docker
systemctl enable docker
systemctl start docker

# Adiciona usuário docker
usermod -aG docker ec2-user

# Instala Docker Compose
mkdir -p /usr/local/lib/docker/cli-plugins

curl -SL https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose

chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Cria diretório mount
mkdir -p /mnt/s3/fs1

# Instala EFS Utils
curl https://amazon-efs-utils.aws.com/efs-utils-installer.sh | \
sh -s -- --install-launch-wizard \
--mount-s3files fs-0ce2fb85a34cb2366 /mnt/s3/fs1

echo "Bootstrap concluído!"
