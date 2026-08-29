FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

# As extensões do DuckDB são instaladas no build, não a cada cold start:
# instalar em runtime deixa a primeira invocação lenta, exige saída para a
# internet e torna a imagem não reproduzível.
ENV DUCKDB_EXTENSION_DIR=/opt/duckdb-extensions
RUN mkdir -p ${DUCKDB_EXTENSION_DIR} && \
    python -c "\
import duckdb, os; \
conn = duckdb.connect(':memory:'); \
conn.execute(\"SET extension_directory='\" + os.environ['DUCKDB_EXTENSION_DIR'] + \"'\"); \
[conn.execute(f'INSTALL {e};') for e in ['aws', 'httpfs', 'parquet', 'avro', 'iceberg']]"

COPY lambda_handler.py ${LAMBDA_TASK_ROOT}/

CMD [ "lambda_handler.lambda_handler" ]
