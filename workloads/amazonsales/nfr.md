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
| Formato de entrada | Parquet + GZIP | `../../platform/aws/modules/dms/main.tf:111-117` |
| Colunas esperadas | 16, declaradas explicitamente | `scripts/dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py:9-26` |
| Volume por carga | **101 linhas na origem, 50 na staged** — medido no ambiente local, dataset `v1` | `local/README.md` |
| Crescimento esperado | **não declarado** — é projeção de negócio, não medição | — |
| Frescor da camada analítica | sob demanda (execução manual do Step Functions) | não há agendamento no Terraform |
| Retenção do dado bruto | **30 dias**, por ciclo de vida do bucket | `../../platform/aws/foundation/main.tf:79-95` |

## Execução

| Requisito | Valor hoje | Origem |
|---|---|---|
| Recursos por job | 3 workers `G.1X` | `aws/infra/main.tf:45-46` |
| Timeout | 60 min | `aws/infra/main.tf:47` |
| Retentativas | **0** | `aws/infra/main.tf:48` |
| Duração de uma execução completa | **43,8 s** local, com 101 linhas — ver a ressalva abaixo | medido no Airflow |
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
| Janela em que dado reprovado fica visível | **9,2 s** local, da escrita até o `ValueError` do portão | medido injetando `user_id` nulo |

## Operação

| Requisito | Valor hoje | Origem |
|---|---|---|
| Quem opera | uma pessoa, em sessões de estudo | `README.md` |
| Disponibilidade exigida | nenhuma — não há consumidor em produção | premissa deste repo |
| Consumidores da camada analítica | nenhum fixo hoje; Metabase/Superset ad hoc | `../../platform/local/` |

## Medições locais — e o que elas não são

Feitas em 2026-08-30 no `platform/local/lakehouse`, com o dataset semeado por
`seed/gerar_dataset.py` (semente 42, 50 produtos, 101 linhas, 51 duplicatas).

| Medição | Valor |
|---|---|
| Pipeline inteira, 8 tarefas | **43,8 s** |
| `stg_table` | 7,2 s |
| `dim_product` / `dim_rating` / `dim_user` (em paralelo) | 8,8 / 8,4 / 8,8 s |
| Portão de qualidade das dimensões | 9,6 s |
| `fact_product_rating` / `fact_sales_category` (em paralelo) | 8,1 / 8,0 s |
| Portão de qualidade dos fatos | 9,1 s |
| Detecção de dado reprovado | **9,2 s** da escrita à falha |
| Consulta de negócio no star schema (Trino, 21 execuções) | **p50 127 ms · p95 197 ms** |
| Volume em disco: origem / lakehouse | 60 KiB / 200 KiB |

**Estes números não são a AWS, e a diferença não é de escala — é de natureza.**
Três ressalvas que precisam acompanhar qualquer leitura deles:

1. **A duração é quase toda partida de JVM.** Com 101 linhas, cada job gasta ~8 s
   subindo Spark e ~0 processando. O número mede o custo fixo do motor, não o
   trabalho. Ele só passa a significar alguma coisa com volume que force
   paralelismo real.
2. **A latência da consulta é de um Trino local sobre 50 linhas em cache de
   página.** Na AWS a mesma pergunta passa por Athena, com bytes escaneados
   cobrados e latência de rede — outra ordem de grandeza e outro modelo de custo.
3. **A janela de exposição depende do encadeamento, não do dado.** Os 9,2 s são
   o tempo de o portão subir e avaliar; na AWS, o `Catch` da máquina de estado
   acrescenta a latência de transição entre estados.

O que estes números **de fato** estabelecem é uma linha de base: se uma mudança
fizer a pipeline local passar de 44 s para 3 minutos com o mesmo dataset, algo
regrediu. É medição de regressão, não de capacidade.

Os campos que continuam **não declarados** — teto de opex, crescimento esperado
— não são medições. São decisões que ninguém tomou ainda, e medir não as
substitui.

## Consequências desta tabela

Três linhas acima são as que mais restringem o desenho atual, e cada uma
sustenta um ADR:

- **Sem consumidor em produção** → é o que torna aceitável o portão de qualidade
  rodar depois da escrita ([`adr/0005`](adr/0005-onde-fica-o-portao-de-qualidade.md)).
  Essa linha mudando, aquele ADR cai.
- **Sem ordenação no CDC** → é o que impede fechar a tabela corretamente e o que
  a Fase 01 do TODO vem resolver ([`adr/0002`](adr/0002-dedup-do-cdc-na-staging.md)).
- **Volume medido é de laboratório, não de produção** → o full refresh do
  [`adr/0004`](adr/0004-politica-de-recarga-por-camada.md) se sustenta em 101
  linhas por construção, e isso não diz nada sobre quando ele deixa de servir.
  O número que falta não é "quanto roda hoje", é **a partir de que volume
  recarregar tudo passa a custar mais que atualizar o que mudou** — e ele só sai
  aumentando o dataset até a duração deixar de ser dominada pela partida da JVM.
