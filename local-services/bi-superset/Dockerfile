FROM apache/superset:3.1.1

USER root

RUN pip install --no-cache-dir \
    "sqlalchemy<2" \
    clickhouse-connect==0.7.8 \
    clickhouse-sqlalchemy==0.2.5 \
    clickhouse-driver==0.2.7 \
    psycopg2-binary

USER superset
