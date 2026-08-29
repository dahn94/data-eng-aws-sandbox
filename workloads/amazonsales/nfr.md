# NFR — pipeline `amazonsales`

Requisitos não-funcionais desta pipeline, quantificados. **Documento vivo:**
quando um número muda aqui, os ADRs que dependem dele viram candidatos a
revisão — cada ADR cita as linhas que pesaram na sua decisão.

"Não medido" é resposta legítima e honesta. Também é lista de tarefas: cada
linha assim é um número que ainda não foi levantado, e vários deles decidem
sozinhos se um ADR continua válido.

**Última revisão:** 2026-08-28

## Dado

| Requisito | Valor hoje | Origem / como foi obtido |
|---|---|---|
| Origem | Postgres (`public.amazon`), via CDC do DMS para Parquet no S3 | `../dms/README.md:24-34` |
| Formato de entrada | Parquet + GZIP | `modules/dms/main.tf:111-117` |
| Colunas esperadas | 16, declaradas explicitamente | `scripts/dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py:9-26` |
| Volume por carga | **não medido** | — |
| Crescimento esperado | **não medido** | — |
| Frescor da camada analítica | sob demanda (execução manual do Step Functions) | não há agendamento no Terraform |
| Retenção do dado bruto | **30 dias**, por ciclo de vida do bucket | `../../platform/aws/foundation/main.tf:79-95` |

## Execução

| Requisito | Valor hoje | Origem |
|---|---|---|
| Recursos por job | 3 workers `G.1X` | `main.tf:45-46` |
| Timeout | 60 min | `main.tf:47` |
| Retentativas | **0** | `main.tf:48` |
| Duração de uma execução completa | **não medido** | — |
| Paralelismo | 3 dimensões em paralelo, depois 2 fatos em paralelo | `scripts/step-functions-definitions/` |

## Custo

Uma linha entre as outras, não o assunto.

| Requisito | Valor hoje | Origem |
|---|---|---|
| Custo parado | **US$0** | Glue e Step Functions só cobram por execução |
| Custo por execução | centavos (Glue ~US$0,44/DPU-hora, mínimo 1 min) | `README.md:81-85` |
| Teto de opex aceitável | **não declarado** | — |

## Correção e recuperação

| Requisito | Valor hoje | Origem |
|---|---|---|
| Recuperação após falha | reexecutar do zero — dims e fatos são full refresh, logo idempotentes | `scripts/glue_common.py:84-97` |
| Staging é idempotente? | sim, `MERGE` por chave primária | `scripts/glue_common.py:99-122` |
| Ordenação de eventos do CDC | **nenhuma** — `dropDuplicates` escolhe uma linha arbitrária por chave | `scripts/dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py:43` |
| Histórico de mudanças da dimensão | **nenhum** — a versão anterior é sobrescrita | `scripts/glue_common.py:84-97` |
| Detecção de mudança de schema na origem | falha o job, com as colunas divergentes nomeadas | `scripts/glue_common.py:66-82` |
| Validação de valor (não de schema) | Glue Data Quality, **depois** da escrita | `scripts/glue_common.py:162-193` |
| Janela em que dado reprovado fica visível | da escrita até a falha do job de DQ — **não medida** | — |

## Operação

| Requisito | Valor hoje | Origem |
|---|---|---|
| Quem opera | uma pessoa, em sessões de estudo | `README.md` |
| Disponibilidade exigida | nenhuma — não há consumidor em produção | premissa deste repo |
| Consumidores da camada analítica | nenhum fixo hoje; Metabase/Superset ad hoc | `../../platform/local/` |

## Consequências desta tabela

Três linhas acima são as que mais restringem o desenho atual, e cada uma
sustenta um ADR:

- **Sem consumidor em produção** → é o que torna aceitável o portão de qualidade
  rodar depois da escrita ([`adr/0005`](adr/0005-onde-fica-o-portao-de-qualidade.md)).
  Essa linha mudando, aquele ADR cai.
- **Sem ordenação no CDC** → é o que impede fechar a tabela corretamente e o que
  a Fase 01 do TODO vem resolver ([`adr/0002`](adr/0002-dedup-do-cdc-na-staging.md)).
- **Volume não medido** → é o que sustenta o full refresh
  ([`adr/0004`](adr/0004-politica-de-recarga-por-camada.md)) e, ao mesmo tempo, o
  que impede saber quando ele deixa de servir. É o número mais urgente a levantar.
