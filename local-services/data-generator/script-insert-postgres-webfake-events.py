"""Gera eventos web sintéticos e insere continuamente no Postgres.

É a origem dos dados que o CDC (DMS ou Debezium) captura. Grava na tabela
`web_events`, que é a que o connector Debezium acompanha.

Configuração por variáveis de ambiente — nenhum default sensível:

    export PGHOST=<endpoint-do-rds>      # output db_instance_address
    export PGPASSWORD=<senha>
    python3 script-insert-postgres-webfake-events.py
"""

import logging
import os
import signal
import sys
import time

import pandas as pd
from fake_web_events import Simulation
from sqlalchemy import create_engine, text

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

TABLE = "web_events"
BATCH_INTERVAL_SECONDS = int(os.environ.get("BATCH_INTERVAL_SECONDS", "60"))

# O default casa com o db_name criado por platform/rds.
DEFAULT_DATABASE = "dataengsandbox"

_running = True


def _stop(signum, frame):
    global _running
    logger.info("Sinal recebido, encerrando após o lote atual...")
    _running = False


def build_engine():
    try:
        password = os.environ["PGPASSWORD"]
        host = os.environ["PGHOST"]
    except KeyError as missing:
        sys.exit(f"erro: variável de ambiente {missing} não definida. Veja o README.")

    user = os.environ.get("PGUSER", "postgres")
    port = os.environ.get("PGPORT", "5432")
    database = os.environ.get("PGDATABASE", DEFAULT_DATABASE)

    logger.info("Conectando em %s:%s/%s como %s", host, port, database, user)
    return create_engine(
        f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{database}",
        pool_pre_ping=True,
    )


def ensure_replica_identity(engine):
    """Faz o Postgres publicar a linha inteira em UPDATE e DELETE.

    Sem REPLICA IDENTITY FULL, o CDC entrega apenas a chave primária no campo
    `before` — e a transformação do job de streaming, que lê `before` em
    deletes, receberia quase tudo nulo.
    """
    with engine.begin() as conn:
        exists = conn.execute(
            text("SELECT to_regclass(:t)"), {"t": f"public.{TABLE}"}
        ).scalar()
        if exists:
            conn.execute(text(f"ALTER TABLE {TABLE} REPLICA IDENTITY FULL"))
            logger.info("REPLICA IDENTITY FULL garantida em %s", TABLE)


def main():
    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    engine = build_engine()
    simulation = Simulation(user_pool_size=100, sessions_per_day=100_000)

    first_batch = True
    while _running:
        events = simulation.run(duration_seconds=1)
        df = pd.DataFrame(events)

        if df.empty:
            logger.info("Nenhum evento neste ciclo.")
        else:
            df.to_sql(TABLE, engine, if_exists="append", index=False)
            logger.info("%d eventos gravados em %s", len(df), TABLE)

            if first_batch:
                # A tabela só existe depois do primeiro to_sql.
                ensure_replica_identity(engine)
                first_batch = False

        for _ in range(BATCH_INTERVAL_SECONDS):
            if not _running:
                break
            time.sleep(1)

    logger.info("Encerrado.")


if __name__ == "__main__":
    main()
