# 0001 — Como levar as mudanças do Postgres ao lake, e com que semântica

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

O Postgres é a origem transacional do repo. As pipelines analíticas precisam das
mudanças dele — insert, update e delete — sem reconsultar a tabela inteira a
cada execução.

Na origem o problema está resolvido: o módulo `rds` sobe com
`rds.logical_replication = 1`, então o WAL está disponível. A pergunta é **quem
lê esse WAL, onde entrega, e — a parte que costuma ser esquecida — que
informação sobrevive à entrega.**

Essa terceira parte é a que importa a longo prazo. Um caminho de CDC não se
julga por levar o dado; julga-se por **o que ele preserva sobre cada mudança**:
se foi insert, update ou delete; em que ordem aconteceram; e o estado anterior.
Perder isso na ingestão é irreversível a jusante — nenhum job de transformação
reconstrói uma ordem que não chegou.

O repositório mantém **os dois** caminhos: DMS em `workloads/dms/` e
Debezium+Kafka em `platform/local/services/streaming-cdc/`. A decisão aqui não é "qual
vence", é qual problema cada um resolve e qual é o caminho padrão.

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Consumidores do evento | **1** (pipelines batch, lendo do S3) | [`nfr.md`](../nfr.md) |
| Coluna de operação (I/U/D) preservada | **não** | [`nfr.md`](../nfr.md) |
| Timestamp de commit / LSN preservado | **não** | [`nfr.md`](../nfr.md) |
| Ordenação entre eventos da mesma chave | **não preservada** | [`nfr.md`](../nfr.md) |
| Garantia de entrega | at-least-once | [`nfr.md`](../nfr.md) |
| Lag de replicação exigido | **não declarado**, não medido | [`nfr.md`](../nfr.md) |
| Quem opera | uma pessoa, em sessões | [`nfr.md`](../nfr.md) |
| Custo parado | ~US$28/mês, **sem pausa possível** | [`nfr.md`](../nfr.md) |

**"Consumidores do evento: 1"** é o requisito que decide o caminho padrão. Um
tópico Kafka existe para entregar o mesmo evento a N assinantes sem reler a
origem; com um assinante só, essa capacidade não é exercida e o cluster vira
infraestrutura sem uso.

As três linhas **"não preservado"** são o que esta decisão custou, e elas não
aparecem no dia em que se escolhe a ferramenta — aparecem quando alguém tenta
fechar a tabela final corretamente.

## Opções consideradas

1. **Consulta incremental por coluna de timestamp.** Sem CDC: não captura
   delete e não vê estado intermediário entre execuções. Rejeitada por
   incapacidade, não por trade-off.
2. **DMS `full-load-and-cdc` com destino S3.** Carga inicial e CDC contínuo num
   recurso gerenciado, gravando Parquet direto no bucket raw. O que ele grava
   é configurável — e a configuração atual descarta operação e timestamp.
3. **Debezium + Kafka.** O evento vira um tópico com envelope completo:
   `before`, `after`, `op` e `ts_ms`. Mais informação preservada, mais
   consumidores possíveis, e quatro processos para manter de pé.

## Decisão

**DMS é o caminho padrão para levar mudanças ao lake; Debezium+Kafka é o caminho
quando o evento precisa de mais de um consumidor ou quando a semântica completa
da mudança importa.** Os dois ficam no repositório.

O requisito que decide é o número de consumidores. Custo entra como restrição
operacional — a instância não pausa, então esquecê-la ligada é o risco real do
mês —, mas não é o que escolhe entre as opções: se houvesse três consumidores, o
Kafka ganharia mesmo custando mais em atenção.

A opção 1 saiu por incapacidade: sem captura de delete, a Fase 01 do TODO não
existe.

**O que esta decisão custou, e não estava registrado em lugar nenhum:** o
endpoint S3 configura compressão e formato, e só. Sem `include_op_for_full_load`
e `timestamp_column_name`, o Parquet que chega ao lake não distingue um delete de
um insert e não carrega instante de commit. A jusante, isso se manifesta como a
impossibilidade de deduplicar corretamente — ver
[`amazonsales/adr/0002`](../../../amazonsales/aws/adr/0002-dedup-do-cdc-na-staging.md).
Não é limitação do DMS: é configuração ausente neste módulo.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Sem coluna de operação: delete indistinguível de insert | **Não é contornado.** É a lacuna central, e a correção é uma linha em `s3_settings` |
| Sem timestamp: eventos da mesma chave sem ordem | **Não é contornado.** A staging escolhe uma versão arbitrária |
| Instância não pausa (~US$28/mês) | Contornado por processo, não por arquitetura: `teardown.sh` e a documentação insistem em destruir ao fim da sessão. `pause.sh` deliberadamente **não** a alcança, porque não há o que pausar |
| Caminho no S3 é contrato manual entre módulos | Contornado por documentação nos dois lados (`raw_output_prefix` aqui, `raw_input_prefix` na pipeline), com aviso de mudar os dois juntos |
| Replication slot órfão prende o WAL | Contornado por instrução explícita de remover o connector antes de destruir o RDS |
| Manter dois caminhos de CDC duplica superfície | Aceito: é o preço de poder estudar os dois modelos sem reescrever a origem |

## Quando esta decisão se inverte

- **Quando aparecer um segundo consumidor do mesmo evento.** É o gatilho
  principal e é binário. O repo já tangencia isso: a pipeline de webevents e o
  ClickHouse consomem o tópico do Debezium — ou seja, no fluxo de streaming a
  decisão **já está invertida**, e por esse motivo exato.
- **Quando a semântica completa da mudança passar a ser requisito.** Precisar de
  `before`/`after`, de metadado de transação ou de contrato em Avro no Schema
  Registry empurra para o Debezium — a menos que a configuração do DMS resolva,
  que é a primeira coisa a tentar e custa uma linha.
- **Quando a sessão de estudo passar a durar dias.** Aí o Debezium local fica
  mais barato, e a decisão se inverte por custo — o único caso em que custo
  decide sozinho.
- **Se o destino deixar de ser objeto no S3.** DMS para S3 é forte porque o
  destino é arquivo; para destino transacional a comparação é outra.

## Consequências

- O CDC funciona ponta a ponta com um recurso gerenciado e nada para operar.
- **A informação sobre a natureza da mudança é perdida na ingestão**, e nenhuma
  transformação a jusante pode recuperá-la. É a consequência mais cara e a menos
  visível.
- A instância é o único recurso do repo que não pausa, o que a torna o item mais
  fácil de esquecer ligado.
- Existem dois caminhos de CDC para manter, documentar e quebrar.
- O item 1 da Fase 01 do TODO começa **aqui**, não na pipeline.

## ⚠️ Inferido

Que o DMS é "o caminho padrão" é leitura da estrutura — ele é root module de
`workloads/` e está no fluxo principal do README, enquanto o `streaming-cdc`
se descreve como "alternativa ao DMS". A hierarquia é consistente, mas nunca foi
declarada. Também é reconstrução minha atribuir a escolha ao número de
consumidores: é o que os requisitos sustentam, mas ninguém escreveu isso. Se o
DMS veio do curso que originou o repo e o Debezium foi acrescentado depois, esse
é o motivo real.

Já a ausência de `include_op_for_full_load` e `timestamp_column_name` **não é
inferência** — é fato verificável no código, e a consequência dela a jusante
também.

## Evidência no repo

- `../../../../platform/aws/modules/dms/main.tf:105-118` — o endpoint S3: só compressão e
  formato; sem coluna de operação, sem timestamp.
- `../../../../platform/aws/modules/dms/main.tf:143` — `migration_type = "full-load-and-cdc"`.
- `workloads/dms/README.md:24-34` — o contrato de caminho no S3 com a pipeline.
- `workloads/dms/README.md:43-54` — custo e ausência de "stop".
- `platform/local/services/streaming-cdc/README.md:3-4` — o Debezium como alternativa.
- `platform/local/services/streaming-cdc/README.md:37-45` — o tópico consumido por dois
  outros componentes: a evidência do fan-out que justifica o Kafka no streaming.
- `platform/local/services/streaming-cdc/README.md:66-70` — o replication slot órfão.
- `workloads/webevents-streaming/aws/scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:76-83`
  — o envelope do Debezium com `before`, `after` e `op`: exatamente a informação
  que o caminho do DMS descarta.
- `README.md:211-212` — o `rds.logical_replication`, pré-requisito comum aos dois.
