# O `apache/iceberg-rest-fixture` é, como o nome diz, um fixture de teste: o
# catálogo padrão dele é um JDBC em memória que NÃO aguenta escrita concorrente.
# Com as três dimensões do amazonsales rodando em paralelo — como a máquina de
# estado faz na AWS — ele devolve:
#
#   ServiceFailureException: Failed to get table ... from catalog rest_backend
#
# A correção é dar um banco de verdade ao catálogo. Só que a imagem não traz o
# driver JDBC do PostgreSQL, e roda com `java -jar`, que ignora CLASSPATH.
# Por isso este Dockerfile acrescenta o driver e troca para `java -cp`.
FROM apache/iceberg-rest-fixture:1.9.2

ARG PG_DRIVER_VERSION=42.7.4
# --chmod importa: sem ele o ADD grava como root com 0600, e o contêiner roda
# como `iceberg` — a JVM não consegue ler o driver e o erro que aparece é
# "No suitable driver found", que não sugere permissão nenhuma.
ADD --chmod=644 \
    https://repo1.maven.org/maven2/org/postgresql/postgresql/${PG_DRIVER_VERSION}/postgresql-${PG_DRIVER_VERSION}.jar \
    /usr/lib/iceberg-rest/postgresql.jar

# Main-Class lido do manifesto do jar original.
CMD ["java", "-cp", "iceberg-rest-adapter.jar:postgresql.jar", \
     "org.apache.iceberg.rest.RESTCatalogServer"]
