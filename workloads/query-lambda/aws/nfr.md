# NFR — `query-lambda`

Requisitos não-funcionais da camada que serve consulta ao lakehouse.
**Documento vivo:** quando um número muda aqui, os ADRs que dependem dele viram
candidatos a revisão.

**Última revisão:** 2026-08-28

## Consulta

| Requisito | Valor hoje | Origem |
|---|---|---|
| Motor | DuckDB, embutido no processo da Lambda | `README.md:3` |
| Alvo | tabelas Iceberg do S3 Tables | `README.md:3` |
| Permissão | **somente leitura**, limitada ao bucket do lakehouse | `README.md:53` |
| Memória | 2048 MB | `infra/main.tf:56` |
| Armazenamento efêmero | 2048 MB | `infra/main.tf:57` |
| Timeout | 900 s (15 min, o máximo da Lambda) | `infra/main.tf:55` |
| Concorrência | **não limitada explicitamente** | — |
| Latência típica de consulta | **não medida** | — |
| Maior resultado já retornado | **não medido** | — |

## Custo

| Requisito | Valor hoje | Origem |
|---|---|---|
| Custo parado | **US$0** — Lambda cobra por invocação | `README.md:28-36` (tabela do repo) |
| Custo por consulta | proporcional a duração × memória | modelo da Lambda |
| Teto de opex aceitável | **não declarado** | — |

## Consequências desta tabela

**2 GB de memória e 2 GB de disco efêmero** são o limite real desta abordagem: o
DuckDB roda dentro de um processo só, então o resultado e o working set precisam
caber aí. É a linha que decide quando esta camada deixa de servir e é preciso um
motor distribuído — registrado em
`adr/0001`.

"Latência não medida" e "maior resultado não medido" são os dois números que
faltam para saber quão perto do limite a coisa está. São também exatamente os
números que o item 8 da Fase 04 do TODO (Athena × Trino × DuckDB × ClickHouse)
vai produzir.
