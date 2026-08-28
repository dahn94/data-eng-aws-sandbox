-- ==================================================================
-- Arquivo: clickhouse/create-table-events.sql
-- Propósito:
--   Define a tabela Kafka-engine `default.web_events_kafka` que consome
--   eventos CDC em formato Avro/Confluent do tópico Kafka e popula a
--   tabela materializada `default.web_events` via `web_events_mv`.
--
-- Fluxo de dados:
--   Postgres (CDC via Debezium) -> Kafka (topic: ecommerce.public.web_events)
--   -> ClickHouse `web_events_kafka` (ENGINE = Kafka, formato AvroConfluent)
--   -> Materialized View `web_events_mv` -> ReplacingMergeTree `web_events`.
--
-- Pontos importantes:
--   - `web_events_kafka` usa colunas `before` e `after` (tuplas) que representam
--     o envelope CDC. A coluna `op` indica a operação (c=insert/u/update/d=delete)
--     e `ts_ms` contém o timestamp em ms.
--   - O conector Kafka espera Schema Registry (Avro Confluent). Atualize
--     `format_avro_schema_registry_url` e `kafka_broker_list` conforme seu ambiente
--     (ex.: `localhost:29092` / `http://localhost:8081` em ambiente local).
--   - A materialized view converte `after.event_timestamp` usando
--     `parseDateTimeBestEffortOrNull` para preencher a coluna `event_timestamp`.
--   - A view filtra deletes (`op != 'd'`) e linhas sem `event_id`.
--
-- Comandos úteis para debug/do deploy local:
--   - Levantar stack local Kafka/Debezium: `cd debezium && docker-compose up -d`
--   - Verificar consumidores Kafka no ClickHouse: `SELECT * FROM system.kafka_consumers;`
--   - Consultar dados materializados: `SELECT * FROM default.web_events LIMIT 10;`
--   - Para recriar a pipeline: dropar `web_events_kafka`, recriar e reiniciar o connector.
--
-- Observações operacionais:
--   - Ajuste timezone/parse conforme formato de `event_timestamp` gerado pelo produtor.
--   - Esta definição presume uso de Avro + Schema Registry; mudar conversores exige
--     alterar configurações do Kafka Connect e possivelmente esta tabela.
-- ==================================================================

-- ------------------------------------------------------------------
-- Tabela: default.web_events_kafka
-- Propósito:
--   Tabela com ENGINE = Kafka que consome mensagens do tópico
--   `ecommerce.public.web_events` em formato `AvroConfluent`.
-- Estrutura:
--   - `before` / `after`: Tuple contendo o payload CDC (linha antes/depois).
--   - `op`: operação CDC ('c' = create, 'u' = update, 'd' = delete).
--   - `ts_ms`: timestamp do evento em milissegundos.
-- Observações operacionais:
--   - Ajuste `kafka_broker_list` e `format_avro_schema_registry_url` para
--     apontarem para seus brokers/Schema Registry locais ou de produção.
--   - O consumo usa o converter Avro Confluent; o Schema Registry deve estar
--     acessível pelo URL configurado.
-- ------------------------------------------------------------------
CREATE TABLE default.web_events_kafka
(
    before Tuple(
        event_id Nullable(String),
        event_timestamp Nullable(String),
        event_type Nullable(String),
        page_url Nullable(String),
        page_url_path Nullable(String),
        referer_url Nullable(String),
        referer_url_scheme Nullable(String),
        referer_url_port Nullable(String),
        referer_medium Nullable(String),
        utm_medium Nullable(String),
        utm_source Nullable(String),
        utm_content Nullable(String),
        utm_campaign Nullable(String),
        click_id Nullable(String),
        geo_latitude Nullable(String),
        geo_longitude Nullable(String),
        geo_country Nullable(String),
        geo_timezone Nullable(String),
        geo_region_name Nullable(String),
        ip_address Nullable(String),
        browser_name Nullable(String),
        browser_user_agent Nullable(String),
        browser_language Nullable(String),
        os Nullable(String),
        os_name Nullable(String),
        os_timezone Nullable(String),
        device_type Nullable(String),
        device_is_mobile Nullable(Bool),
        user_custom_id Nullable(String),
        user_domain_id Nullable(String)
    ),

    after Tuple(
        event_id Nullable(String),
        event_timestamp Nullable(String),
        event_type Nullable(String),
        page_url Nullable(String),
        page_url_path Nullable(String),
        referer_url Nullable(String),
        referer_url_scheme Nullable(String),
        referer_url_port Nullable(String),
        referer_medium Nullable(String),
        utm_medium Nullable(String),
        utm_source Nullable(String),
        utm_content Nullable(String),
        utm_campaign Nullable(String),
        click_id Nullable(String),
        geo_latitude Nullable(String),
        geo_longitude Nullable(String),
        geo_country Nullable(String),
        geo_timezone Nullable(String),
        geo_region_name Nullable(String),
        ip_address Nullable(String),
        browser_name Nullable(String),
        browser_user_agent Nullable(String),
        browser_language Nullable(String),
        os Nullable(String),
        os_name Nullable(String),
        os_timezone Nullable(String),
        device_type Nullable(String),
        device_is_mobile Nullable(Bool),
        user_custom_id Nullable(String),
        user_domain_id Nullable(String)
    ),

    op String,
    ts_ms Nullable(UInt64)
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'ec2-13-58-145-36.us-east-2.compute.amazonaws.com:29092',
    kafka_topic_list = 'ecommerce.public.web_events',
    kafka_group_name = 'clickhouse_web_events_new',
    kafka_format = 'AvroConfluent',
    format_avro_schema_registry_url = 'http://ec2-13-58-145-36.us-east-2.compute.amazonaws.com:8081',
    kafka_num_consumers = 1;



-- ------------------------------------------------------------------
-- Verificação de consumidores Kafka no ClickHouse
-- Propósito: consultar `system.kafka_consumers` para inspecionar grupos
-- e partições consumidas pela tabela Kafka-engine.
-- Uso típico: executar após levantar a stack Kafka/Connect para validar
-- que o ClickHouse está consumindo os tópicos esperados.
-- ------------------------------------------------------------------
SELECT *
FROM system.kafka_consumers;

-- ------------------------------------------------------------------
-- Tabela materializada final: default.web_events
-- Propósito:
--   Armazenar o estado final dos eventos extraídos do envelope CDC.
-- Estratégia:
--   - `ENGINE = ReplacingMergeTree(_ts_ms)`: usa `_ts_ms` como versão
--     para resolver atualizações concorrentes (merge/replace behavior).
--   - `ORDER BY event_id`: chave de ordenação; avalie índices se necessário.
-- Colunas chave:
--   - `event_timestamp`: tipo `DateTime`, preenchido via parsing na MV.
--   - `_op`: operação CDC original, mantida para auditoria.
-- Observação: garanta que `_ts_ms` esteja presente e incremental no fluxo
-- para que o ReplacingMergeTree funcione corretamente.
-- ------------------------------------------------------------------
CREATE TABLE default.web_events
(
    event_id String,
    event_timestamp DateTime,
    event_type String,
    page_url String,
    page_url_path String,
    referer_url String,
    referer_medium String,
    utm_medium String,
    utm_source String,
    utm_campaign String,
    geo_country String,
    browser_name String,
    os_name String,
    device_type String,
    device_is_mobile Bool,
    user_custom_id String,
    user_domain_id String,
    _op String,
    _ts_ms UInt64
)
ENGINE = ReplacingMergeTree(_ts_ms)
ORDER BY event_id;


-- ------------------------------------------------------------------
-- Materialized View: default.web_events_mv
-- Propósito:
--   Consumir a tabela Kafka (`web_events_kafka`), extrair o payload `after`,
--   transformar campos (ex.: parsing de timestamp) e inserir na tabela
--   `default.web_events`.
-- Comportamento:
--   - Converte `after.event_timestamp` usando
--     `parseDateTimeBestEffortOrNull` para suportar vários formatos.
--   - Filtra registros com `after.event_id IS NULL` e operações de delete
--     (`op != 'd'`). Para preservar deletes, remova o filtro `op != 'd'`.
--   - Mantém `_op` e `_ts_ms` para rastreabilidade/versão.
-- Quando ajustar:
--   - Se o produtor mudar o envelope CDC (nomes de campos), atualize
--     os mapeamentos `after.<campo>` neste SELECT.
-- ------------------------------------------------------------------
CREATE MATERIALIZED VIEW default.web_events_mv
TO default.web_events
AS
SELECT
    after.event_id AS event_id,
    parseDateTimeBestEffortOrNull(after.event_timestamp) AS event_timestamp,
    after.event_type AS event_type,
    after.page_url AS page_url,
    after.page_url_path AS page_url_path,
    after.referer_url AS referer_url,
    after.referer_medium AS referer_medium,
    after.utm_medium AS utm_medium,
    after.utm_source AS utm_source,
    after.utm_campaign AS utm_campaign,
    after.geo_country AS geo_country,
    after.browser_name AS browser_name,
    after.os_name AS os_name,
    after.device_type AS device_type,
    after.device_is_mobile AS device_is_mobile,
    after.user_custom_id AS user_custom_id,
    after.user_domain_id AS user_domain_id,
    op AS _op,
    ts_ms AS _ts_ms
FROM default.web_events_kafka
WHERE after.event_id IS NOT NULL
  AND op != 'd';

