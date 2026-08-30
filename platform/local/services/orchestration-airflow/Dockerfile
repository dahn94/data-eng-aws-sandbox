# A imagem do Airflow não traz o cliente do Docker, e o DAG dispara os jobs com
# `docker exec` no contêiner do lakehouse. Só o cliente entra aqui — o daemon
# continua sendo o da sua máquina, alcançado pelo socket montado.
#
# Instalar por pip como root é bloqueado pela imagem, então o que precisa vir de
# fora vem aqui, em tempo de build.
FROM apache/airflow:3.1.3

USER root

# Binário estático oficial, escolhido pela arquitetura de quem constrói.
ARG DOCKER_VERSION=27.5.1
RUN set -eux; \
    arch="$(uname -m)"; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${arch}/docker-${DOCKER_VERSION}.tgz" \
      -o /tmp/docker.tgz; \
    tar -xzf /tmp/docker.tgz -C /tmp; \
    install -m 0755 /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker /tmp/docker.tgz; \
    docker --version

USER airflow
