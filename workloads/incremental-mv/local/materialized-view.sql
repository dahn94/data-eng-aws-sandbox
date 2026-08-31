-- A forma local do incremental-mv, em ClickHouse.
--
-- Na AWS este workload usa Redshift com AUTO REFRESH; não existe Redshift em
-- contêiner. O que se pode exercitar localmente é o MECANISMO, que é sobre o
-- que o adr/0001 fala: você declara o resultado que deve valer sempre, e o
-- motor decide quando recomputar.
--
-- A diferença honesta: no Redshift o refresh é assíncrono e o motor escolhe o
-- momento; no ClickHouse a view é atualizada na escrita, de forma incremental.
-- Os dois tiram de você a decisão do "quando" — que é o ponto do ADR — mas por
-- caminhos diferentes.
--
--   docker compose -f ../../../platform/local/olap-clickhouse/docker-compose.yml up -d
--   docker exec -i incremental-mv-clickhouse clickhouse-client --multiquery < materialized-view.sql

DROP VIEW IF EXISTS receita_por_hora;
DROP TABLE IF EXISTS receita_por_hora_dados;
DROP TABLE IF EXISTS vendas;

-- A tabela base, com o mesmo formato do contrato em workloads/DATASET.md.
CREATE TABLE vendas (
    order_id    UInt64,
    customer_id UInt64,
    pedido_em   DateTime,
    valor       Decimal(12, 2),
    status      String
) ENGINE = MergeTree ORDER BY (pedido_em, customer_id);

-- O destino do agregado. Somas parciais, para o motor combinar de forma
-- incremental em vez de recomputar tudo.
CREATE TABLE receita_por_hora_dados (
    hora     DateTime,
    pedidos  AggregateFunction(count, UInt64),
    receita  AggregateFunction(sum, Decimal(12, 2))
) ENGINE = AggregatingMergeTree ORDER BY hora;

-- Aqui está o mecanismo: ninguém agenda nada. Toda escrita em `vendas`
-- atualiza este agregado, incrementalmente.
CREATE MATERIALIZED VIEW receita_por_hora TO receita_por_hora_dados AS
SELECT
    toStartOfHour(pedido_em) AS hora,
    countState(order_id)     AS pedidos,
    sumState(valor)          AS receita
FROM vendas
GROUP BY hora;
