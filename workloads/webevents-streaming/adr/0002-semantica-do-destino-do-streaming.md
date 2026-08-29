# 0002 — Que pergunta o índice de destino consegue responder

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

O job consome o envelope do Debezium, que descreve cada mudança com precisão:
`before` (estado anterior), `after` (estado novo), `op` (insert, update, delete)
e `ts_ms` (instante). Toda a informação necessária para reconstruir o estado da
tabela de origem está ali.

O que se faz com essa informação decide o que o destino **é**. Duas leituras
possíveis do mesmo fluxo:

- um **espelho**: o destino reflete o estado atual da tabela de origem — um
  update substitui, um delete remove;
- um **log**: o destino acumula tudo que aconteceu — o update vira um registro
  novo ao lado do anterior, o delete vira mais um registro.

As duas respondem perguntas diferentes e são incompatíveis. "Quantos produtos
existem hoje" só o espelho responde; "quantas vezes este produto mudou" só o log
responde. Escolher sem perceber que se escolheu é o erro clássico.

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Perguntas do destino | análise de comportamento por período | inferido do uso (OpenSearch Dashboards) |
| Garantia de entrega | **at-least-once** | [`nfr.md`](../nfr.md) |
| Chave de documento no destino | **nenhuma** — id gerado automaticamente | [`nfr.md`](../nfr.md) |
| Modo de saída | `append` | [`nfr.md`](../nfr.md) |
| Offset inicial | `earliest` | [`nfr.md`](../nfr.md) |
| Janela / watermark / evento atrasado | **nenhum tratamento** | [`nfr.md`](../nfr.md) |
| Reprocessamento | apagar o checkpoint e reler o tópico | [`nfr.md`](../nfr.md) |

Os requisitos 2, 3 e 4 juntos **já determinam a resposta**, e essa é a parte que
importa: sem chave de documento, `append` e at-least-once tornam o espelho
impossível de construir, porque nada no destino identifica "a mesma entidade"
para substituir ou remover.

Ou seja, a semântica não foi escolhida numa reunião — ela caiu como consequência
de três opções técnicas. Registrar isso é o objetivo deste ADR.

## Opções consideradas

1. **Espelho do estado.** Usar a chave primária como id do documento, `upsert`
   no update e `delete` na operação `d`. Responde "como está agora", com custo de
   idempotência resolvido (reprocessar converge para o mesmo estado).
2. **Log de eventos com `append`.** Cada mensagem vira um documento novo,
   inclusive o delete, que entra como um registro carregando a linha que existia
   antes. Responde "o que aconteceu ao longo do tempo".
3. **Os dois destinos**, um índice de estado e outro de eventos. Máxima
   capacidade analítica, duas escritas e duas coisas para manter em sincronia.

## Decisão

Opção 2: o índice é um **log de eventos**, não um espelho.

O job trata `op == 'd'` pegando o conteúdo de `before` — porque num delete o
`after` vem vazio — e o escreve como mais um documento, com a coluna `op`
preservada ao lado de `ts_ms`. O delete, portanto, **adiciona** informação em vez
de remover.

O requisito que decide é a combinação de `append` com ausência de chave de
documento. Preservar `op` e `ts_ms` no documento é o que salva a decisão de ser
uma perda: com esses dois campos, uma consulta consegue reconstruir o estado
mais recente por chave, ordenando por `ts_ms` e ficando com o último — o espelho
vira responsabilidade de quem consulta, em vez de propriedade do índice.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Índice não responde "estado atual" diretamente | Contornado no lado da consulta: `op` e `ts_ms` estão em cada documento, então dá para ordenar por chave e ficar com o último |
| At-least-once sem chave: reprocessar duplica documentos | **Não é contornado.** Reprocessar do zero exige apagar o índice junto com o checkpoint, e isso não está escrito em lugar nenhum |
| Índice cresce indefinidamente | **Não é contornado.** Não há política de retenção nem rollover declarados |
| Sem watermark: evento atrasado entra como se fosse recente | **Não é contornado.** Não há tratamento de tempo de evento; é o item 7 da Fase 03 do TODO |
| `failOnDataLoss = false` esconde perda de mensagem | Aceito para ambiente de estudo — em produção, mascara exatamente o incidente que se precisa ver |
| Delete some da análise de estado se ninguém filtrar `op` | Parcialmente: o campo existe e está documentado aqui; nada obriga a usá-lo |

Duas linhas se combinam de um jeito que merece destaque: **reprocessar duplica**
e **não há retenção**. Juntas, significam que cada reprocessamento deixa lixo
permanente no índice. É a consequência operacional mais provável de acontecer na
prática, e a menos óbvia.

## Quando esta decisão se inverte

- **Quando alguém consultar o índice esperando o estado atual.** É o gatilho
  real, e ele vem de fora: no dia em que um dashboard contar "produtos ativos" e
  o número vier errado por incluir deletes, a semântica de log deixou de servir.
  A correção é a opção 1: chave de documento igual à chave primária, e delete de
  verdade.
- **Quando o custo de armazenamento do índice incomodar** — sintoma de que o log
  cresce sem retenção. A resposta pode ser política de rollover em vez de mudar
  a semântica.
- **Quando exactly-once virar requisito.** Aí não basta chave de documento: entra
  escrita idempotente com controle de offset, e é o momento em que pousar no
  Iceberg (item 7 da Fase 03) passa a ser mais fácil do que continuar no
  OpenSearch.
- **Quando evento atrasado passar a importar** — análise por janela de sessão,
  por exemplo. Watermark e política de atraso não têm como ser acrescentados sem
  repensar o destino.

## Consequências

- O índice responde bem perguntas sobre atividade ao longo do tempo, que são as
  que o painel faz hoje.
- O índice **não** é fonte confiável para "o que existe agora", e nada nele
  sinaliza isso a quem consulta.
- Preservar `op` e `ts_ms` mantém a porta aberta: o estado é derivável na
  consulta, ainda que caro.
- O fluxo de streaming **não alimenta o lakehouse**. Toda a semântica de tabela —
  MERGE, snapshot, time travel — que a pipeline batch tem, esta não tem. É a
  maior lacuna da arquitetura de streaming atual.

## Evidência no repo

- `workloads/webevents-streaming/scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:74-83`
  — o tratamento do envelope: `before` quando `op == 'd'`, `after` no resto, com
  `op` e `ts_ms` preservados no documento.
- `workloads/webevents-streaming/scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:93-108`
  — a escrita: `append`, sem `opensearch.mapping.id`, logo sem chave de documento.
- `workloads/webevents-streaming/scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:61-62`
  — `startingOffsets = earliest` e `failOnDataLoss = false`.
- `workloads/webevents-streaming/README.md` — seção "Checkpoint":
  reprocessar do zero é apagar o caminho do checkpoint, sem menção ao índice.
