# 0004 — Reconstruir a camada do zero ou atualizar só o que mudou

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

A cada execução, a pipeline precisa decidir, para cada tabela que escreve, entre
duas estratégias: reconstruir a tabela inteira a partir da origem, ou aplicar
apenas as mudanças sobre o que já está lá.

A escolha parece de desempenho e é, na verdade, de **correção**. Full refresh é
idempotente por construção: rodar duas vezes dá o mesmo resultado que rodar uma.
Carga incremental acumula estado, e estado acumulado guarda os erros das
execuções anteriores — uma reexecução não os corrige.

A pergunta não tem uma resposta só: cada camada tem restrições diferentes.

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Volume por carga | **não medido** | [`nfr.md`](../nfr.md) |
| Retenção do dado bruto | **30 dias** (ciclo de vida do bucket) | [`nfr.md`](../nfr.md) |
| Recuperação após falha | reexecutar do zero | [`nfr.md`](../nfr.md) |
| Retentativas do job | 0 | [`nfr.md`](../nfr.md) |
| Frescor exigido | sob demanda | [`nfr.md`](../nfr.md) |
| Duração de uma execução | **não medida** | [`nfr.md`](../nfr.md) |

Duas linhas se contradizem, e essa tensão é o coração da decisão:

- **"Recuperação = reexecutar do zero"** só é verdade se a tabela for
  reconstruível a partir do que ainda existe.
- **"Retenção do bruto = 30 dias"** significa que o histórico completo **não**
  existe para sempre. Passados 30 dias, nenhuma tabela é reconstruível a partir
  da raw.

## Opções consideradas

1. **Full refresh em tudo** (`INSERT OVERWRITE`). Idempotente, simples, sempre
   reproduzível — e proporcional ao volume total a cada execução.
2. **Incremental em tudo** (`MERGE`). Proporcional ao que mudou. Acumula estado e
   perde a idempotência.
3. **Estratégia por camada**: incremental onde o dado histórico é insubstituível,
   full refresh onde a tabela é derivada e reconstruível.

## Decisão

Opção 3, com a regra: **incremental onde a perda é irreversível, full refresh
onde a tabela é derivada.**

- **Staging — `MERGE` por chave.** É a única camada que acumula histórico que não
  existe em mais lugar nenhum: passados os 30 dias de retenção do bucket raw, o
  Parquet de origem some. Se a staging fosse full refresh, ela conteria só o que
  a última carga trouxe. É o requisito de retenção que decide, não desempenho.
- **Dimensões e fatos — `INSERT OVERWRITE`.** São inteiramente derivados da
  staging por `distinct` e `groupBy`. Nada neles é insubstituível, então
  reconstruir é sempre correto e nunca perde informação. Em troca, ganha-se
  idempotência: com `max_retries = 0`, a recuperação de qualquer falha é
  reexecutar, e isso só é seguro porque a escrita é sobrescrita total.

O requisito que decide o lado derivado é o volume — **e ele não está medido.**
Full refresh é a escolha certa em volume pequeno e a errada em volume grande; a
pipeline está do lado certo hoje por uma premissa não verificada. É a lacuna mais
importante deste ADR e o número mais urgente do `nfr.md`.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Full refresh custa o volume total a cada execução | Aceito enquanto o volume for pequeno — **sem medição que confirme** |
| `INSERT OVERWRITE` deixa a tabela vazia se o job morrer no meio | Iceberg torna a escrita atômica: o snapshot só é publicado ao final, então um leitor concorrente vê a versão anterior, nunca uma tabela pela metade |
| Staging acumula linha que já foi apagada na origem | **Não é contornado** — é a consequência direta de [0002](./0002-dedup-do-cdc-na-staging.md), que não trata delete |
| Erro que entrou na staging fica lá para sempre | Parcialmente: dá para reverter por time travel do Iceberg, mas é operação manual e não há procedimento escrito |
| Retenção de 30 dias apaga a origem | Aceito: a staging passa a ser a origem de verdade a partir do dia 31 — **e ela não tem backup próprio** |

A última linha é a mais séria e não estava documentada em lugar nenhum: depois de
30 dias, a staging é o único lugar onde o dado existe, e a estratégia de
recuperação declarada ("reexecutar do zero") deixa de funcionar para ela.

## Quando esta decisão se inverte

- **Quando a duração da execução completa incomodar** — é o sintoma observável de
  que o full refresh saiu de escala, e chega antes de o custo doer. O gatilho
  prático: quando reexecutar deixar de ser a primeira reação a uma falha.
- **Quando o volume for medido e passar da ordem de milhões de linhas por
  dimensão.** Aí `INSERT OVERWRITE` vira desperdício e a dimensão passa a
  incremental — o que, por sua vez, exige a ordenação que
  [0002](./0002-dedup-do-cdc-na-staging.md) não tem.
- **Quando o frescor exigido passar de "sob demanda" para "de hora em hora".**
  Full refresh de hora em hora paga o volume inteiro toda hora.
- **Quando alguém precisar reconstruir a staging.** No dia em que isso for
  necessário e o dado bruto já tiver expirado, esta decisão terá cobrado seu
  preço, e a resposta é backup da staging ou retenção maior — não mudar a
  estratégia de carga.

## Consequências

- Reexecutar é sempre seguro para dimensões e fatos, o que torna
  `max_retries = 0` uma escolha coerente e não um descuido.
- A staging é a única tabela com estado real, e portanto a única que precisa de
  cuidado em operação.
- O custo por execução é proporcional ao volume total, não ao que mudou.
- `write_table` e `merge_table` coexistem em `glue_common`, e qual usar é decisão
  de cada job. Nada no código impede usar o errado — a regra vive neste
  documento, não numa restrição de código.

## Evidência no repo

- `workloads/amazonsales/scripts/glue_common.py:84-97` — o
  `write_table` com `INSERT OVERWRITE`, e o comentário que declara a intenção:
  "é um full refresh de propósito: os volumes deste sandbox são pequenos e o
  resultado é sempre reproduzível".
- `workloads/amazonsales/scripts/glue_common.py:99-122` — o
  `merge_table`, usado só pela staging.
- `workloads/amazonsales/scripts/dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py:45`
  — a staging chamando `merge_table`.
- `workloads/amazonsales/scripts/dataeng-sandbox-amazonsales-dw-dim-product-s3tables.py:23`
  — a dimensão chamando `write_table`.
- `platform/aws/foundation/main.tf:86-93` — o ciclo de vida de 30 dias que torna
  a staging insubstituível.
- `workloads/amazonsales/aws/infra/main.tf:48` — `max_retries = 0`.
