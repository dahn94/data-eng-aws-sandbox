# NFR — ingestão por CDC (`dms`)

Requisitos não-funcionais do caminho que leva as mudanças do Postgres ao S3.
**Documento vivo:** quando um número muda aqui, os ADRs que dependem dele viram
candidatos a revisão.

**Última revisão:** 2026-08-28

## Captura

| Requisito | Valor hoje | Origem |
|---|---|---|
| Origem | Postgres com `rds.logical_replication = 1` | `../../sources/rds/README.md:36` |
| Modo | `full-load-and-cdc` — carga inicial e CDC contínuo | `modules/dms/main.tf:143` |
| Destino | Parquet + GZIP no S3 raw | `modules/dms/main.tf:111-117` |
| Caminho de saída | `<bucket_folder>/<schema>/<tabela>/` | `README.md:24-34` |
| Coluna de operação (I/U/D) | **ausente** — `include_op_for_full_load` não configurado | `modules/dms/main.tf:111-117` |
| Timestamp de commit | **ausente** — `timestamp_column_name` não configurado | `modules/dms/main.tf:111-117` |
| Lag de replicação | **não medido** | — |
| Consumidores do evento | **1** (as pipelines batch, lendo do S3) | `README.md:24-34` |

## Custo

| Requisito | Valor hoje | Origem |
|---|---|---|
| Custo parado | **~US$28/mês** — `dms.t3.micro` + 20 GB | `README.md:43-54` |
| Pode ser pausado? | **não** — a instância não tem "stop", só delete | `README.md:43-54` |
| Alternativa de custo zero | Kafka + Debezium local (`local-services/streaming-cdc`) | `../../local-services/streaming-cdc/README.md:3-4` |

## Correção e recuperação

| Requisito | Valor hoje | Origem |
|---|---|---|
| Garantia de entrega | at-least-once (o consumidor precisa deduplicar) | característica do DMS |
| Ordenação entre eventos da mesma chave | **não preservada no arquivo de saída** | consequência da ausência de timestamp/LSN |
| Delete é capturado? | sim pelo CDC, mas **indistinguível** de insert no arquivo, por falta da coluna de operação | `modules/dms/main.tf:111-117` |
| Risco na origem | replication slot órfão prende o WAL e pode encher o disco | `../../local-services/streaming-cdc/README.md:66-70` |

## Consequências desta tabela

As três linhas em **negrito** na seção de captura — sem coluna de operação, sem
timestamp de commit, sem ordenação — são a razão de a pipeline `amazonsales` não
conseguir fechar a tabela final corretamente hoje, e a razão de o item 1 da Fase
01 do TODO exigir alterar **este módulo** antes de criar qualquer job de MERGE.
Está registrado em [`adr/0001`](adr/0001-captura-de-mudancas-do-postgres.md).

A linha "consumidores do evento = 1" é a que sustenta escolher DMS em vez de
Kafka. Ela virando 2, aquele ADR cai.
