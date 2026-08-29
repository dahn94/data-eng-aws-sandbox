# NFR — pipeline `webevents-streaming`

Requisitos não-funcionais do fluxo de eventos web em tempo real.
**Documento vivo:** quando um número muda aqui, os ADRs que dependem dele viram
candidatos a revisão.

**Última revisão:** 2026-08-28

## Dado

| Requisito | Valor hoje | Origem |
|---|---|---|
| Origem | tópico Kafka `ecommerce.public.web_events`, Avro do Debezium | `../../platform/local/streaming-cdc/README.md:37-45` |
| Schema | lido do Schema Registry **em runtime**, versão `latest` | `scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:47-52` |
| Destino | índice do OpenSearch | `scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:93-108` |
| O dado pousa no lakehouse? | **não** — o fluxo vai direto ao OpenSearch | `scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:93-108` |
| Vazão | **não medida** | — |
| Latência ponta a ponta | **não medida** (micro-batch, sem `trigger` explícito) | — |

## Entrega e recuperação

| Requisito | Valor hoje | Origem |
|---|---|---|
| Garantia de entrega | **at-least-once** — sem chave de documento, reprocessar duplica | `scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:93-108` |
| Modo de saída | `append` | `scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:106` |
| Offset inicial | `earliest` | `scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:62` |
| Perda de dado no tópico | tolerada (`failOnDataLoss = false`) | `scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:61` |
| Checkpoint | `s3://<prefixo>-lake-logs-<amb>/spark-checkpoints/<amb>/...` | `README.md` |
| Como reprocessar do zero | apagar o caminho do checkpoint antes de reiniciar | `README.md` |
| Retentativas do job | **0** | `main.tf:56` |
| Janela, watermark, evento atrasado | **nenhum tratamento** | não há `withWatermark` no script |

## Governança

| Requisito | Valor hoje | Origem |
|---|---|---|
| Dado pessoal no destino | **descartado antes de sair do job**: IP, user agent, idioma, SO, dispositivo, id customizado | `scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:24-35` |
| Senha do destino | Secrets Manager; o job recebe só o ARN | `README.md` |
| Certificado do destino | autoassinado, validação desligada | `scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:103-104` |

## Custo

| Requisito | Valor hoje | Origem |
|---|---|---|
| Custo parado | **US$0** se o job estiver parado | Glue cobra enquanto roda |
| Custo rodando | **~US$0,088/hora ≈ US$64/mês** — 2 workers `G.025X` | `README.md` |
| Teto de opex aceitável | **não declarado** | — |

## Consequências desta tabela

- **At-least-once sem chave de documento** somado a **`append`** é o que define a
  semântica do índice: ele é um log de eventos, não um espelho do estado da
  tabela de origem. Registrado em
  [`adr/0002`](adr/0002-semantica-do-destino-do-streaming.md).
- **O dado não pousa no lakehouse** é a maior lacuna da arquitetura atual e o que
  o item 7 da Fase 03 do TODO vem resolver — sem isso não há janela, watermark
  nem exactly-once para estudar.
- **Custo rodando ≈ US$64/mês** é o único item deste repo que cobra por hora
  estando "no fluxo padrão", e é por isso que o job precisa ser parado no fim da
  sessão. Aqui custo é restrição operacional, não critério de desenho.
