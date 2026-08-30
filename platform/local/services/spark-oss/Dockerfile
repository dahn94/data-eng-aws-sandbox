# Apache Spark de código aberto, mais as mesmas dependências do job.
#
# Sem Great Expectations aqui, o portão de qualidade não roda no motor aberto —
# e é justamente nele que se prova que o portão não depende da AWS.
FROM spark:3.5.7-scala2.12-java17-python3-ubuntu

USER root
RUN pip install --no-cache-dir great_expectations==1.21.0
USER spark
