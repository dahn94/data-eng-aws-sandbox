# A imagem oficial do Airflow não traz o provider de Kubernetes, e é ele que
# permite ao DAG criar um pod por tarefa — o análogo do `glue:startJobRun` da
# máquina de estado, onde cada job é uma execução isolada.
#
# Instalar por pip como root é bloqueado pela imagem, então isto roda como
# `airflow`, em tempo de build.
FROM apache/airflow:3.1.3

USER airflow

ARG AIRFLOW_VERSION=3.1.3
ARG PYTHON_VERSION=3.12
RUN pip install --no-cache-dir \
      "apache-airflow-providers-cncf-kubernetes" \
      --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"
