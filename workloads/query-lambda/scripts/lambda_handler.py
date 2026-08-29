"""Consulta as tabelas Iceberg do S3 Tables com DuckDB, dentro de uma Lambda.

Aceita invocação direta e Function URL. Em ambos os casos recebe uma query SQL
e um ARN de catálogo.

Aviso de segurança: esta função executa o SQL que recebe, sem restrição. É o
que a torna útil como console de consulta, e é também por isso que a Function
URL só é criada com autenticação AWS_IAM. Nunca exponha esta função com
`authorization_type = "NONE"`: seria um executor de SQL aberto na internet.
As permissões IAM da função são somente leitura, o que limita o estrago.
"""

import json
import logging
import os

import duckdb

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Extensões instaladas no build da imagem (veja o Dockerfile), não a cada
# cold start.
EXTENSION_DIR = os.environ.get("DUCKDB_EXTENSION_DIR", "/opt/duckdb-extensions")
EXTENSIONS = ["aws", "httpfs", "parquet", "avro", "iceberg"]

MAX_ROWS = int(os.environ.get("MAX_ROWS", "1000"))


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def _connect():
    conn = duckdb.connect(":memory:")
    conn.execute(f"SET extension_directory='{EXTENSION_DIR}'")
    for ext in EXTENSIONS:
        conn.execute(f"LOAD {ext};")

    # Credenciais vêm da role da própria Lambda.
    conn.execute("CREATE SECRET (TYPE s3, PROVIDER credential_chain);")
    return conn


def _read_params(event):
    """Extrai (catalog_arn, query) tanto de Function URL quanto de invocação direta."""
    if "queryStringParameters" in event:
        params = event.get("queryStringParameters") or {}
    else:
        params = event

    catalog_arn = params.get("catalog_arn") or os.environ.get("DEFAULT_CATALOG")
    query = params.get("query")
    return catalog_arn, query


def lambda_handler(event, context):
    catalog_arn, query = _read_params(event)

    if not catalog_arn or not query:
        return _response(400, {
            "error": "Parâmetros obrigatórios ausentes",
            "required": ["query", "catalog_arn"],
            "note": "catalog_arn pode vir da variável de ambiente DEFAULT_CATALOG",
        })

    conn = None
    try:
        conn = _connect()

        try:
            conn.execute(
                "ATTACH ? AS s3_tables_db (TYPE iceberg, ENDPOINT_TYPE s3_tables);",
                [catalog_arn],
            )
        except Exception as exc:
            logger.error("Falha ao anexar o catálogo: %s", exc)
            return _response(502, {
                "error": "Não foi possível conectar ao catálogo S3 Tables",
                "details": str(exc),
            })

        try:
            cursor = conn.execute(query)
            columns = [desc[0] for desc in cursor.description]
            rows = cursor.fetchmany(MAX_ROWS)
        except Exception as exc:
            logger.error("Falha ao executar a query: %s", exc)
            return _response(400, {
                "error": "Erro ao executar a query",
                "details": str(exc),
                "suggestions": [
                    "Confirme que a tabela existe no catálogo anexado",
                    "Confirme o formato do ARN do S3 Tables",
                    "Confirme as permissões IAM da função sobre o bucket",
                ],
            })

        data = [dict(zip(columns, row)) for row in rows]
        logger.info("Query executada: %d linhas", len(data))

        return _response(200, {
            "data": data,
            "metadata": {
                "row_count": len(data),
                "column_names": columns,
                "truncated": len(data) == MAX_ROWS,
            },
        })

    except Exception as exc:
        logger.exception("Erro inesperado")
        return _response(500, {"error": "Erro inesperado", "details": str(exc)})

    finally:
        if conn is not None:
            conn.close()
