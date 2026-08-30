# 0001 — Como impedir que uma mudança na origem entre calada na pipeline

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

A pipeline lê Parquet que o DMS gravou a partir de uma tabela do Postgres. O
Parquet carrega o próprio schema, então o Spark consegue inferi-lo sozinho — e é
aí que mora o problema.

Se alguém altera a tabela na origem (renomeia coluna, troca `numeric` por
`text`, acrescenta campo), o Parquet muda junto. Com schema inferido, a pipeline
**aceita** a mudança: a tabela Iceberg de destino passa a ter outro formato, ou
uma coluna passa a ter outro tipo, e nada falha. O erro aparece dias depois, num
número errado num dashboard, longe da causa.

A pergunta é onde essa divergência deve ser detectada, e o que deve acontecer
quando ela for.

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Colunas esperadas | 16, declaradas explicitamente | [`nfr.md`](../nfr.md) |
| Controle sobre a origem | **nenhum** — o Postgres é de outro root module | [`nfr.md`](../nfr.md) |
| Detecção de mudança de schema | falhar o job, nomeando as colunas divergentes | [`nfr.md`](../nfr.md) |
| Recuperação após falha | reexecutar do zero | [`nfr.md`](../nfr.md) |
| Consumidor em produção | nenhum | [`nfr.md`](../nfr.md) |

A linha que decide é **"controle sobre a origem: nenhum"**. Se a pipeline
pudesse negociar mudanças com quem mantém o Postgres, um schema evolutivo seria
seguro; sem esse canal, toda mudança é uma surpresa, e surpresa absorvida em
silêncio vira erro de negócio semanas depois.

A linha "recuperação = reexecutar do zero" é o que torna barato falhar: o custo
de um falso positivo é uma reexecução, e o custo de um falso negativo é dado
errado publicado. A assimetria justifica falhar cedo.

## Opções consideradas

1. **Inferir o schema do Parquet.** Zero manutenção, absorve mudança de origem
   automaticamente — e é justamente a absorção silenciosa que se quer evitar.
2. **Inferir, mas evoluir a tabela de destino** (schema evolution do Iceberg,
   `mergeSchema`). Correto quando a mudança é aditiva e esperada; perigoso
   quando é troca de tipo, e continua sem avisar ninguém.
3. **Declarar o schema esperado no código e falhar quando a realidade
   divergir.** A pipeline carrega um contrato explícito do que espera receber.

## Decisão

Opção 3, em duas camadas que resolvem problemas diferentes:

**Na entrada** (`stg`), um dicionário `COLUMN_TYPES` declara as 16 colunas e
seus tipos. O job faz `cast` para esses tipos e `select` apenas dessas colunas.
Coluna nova na origem é ignorada; coluna que sumiu quebra na hora.

**Na escrita** (`glue_common.assert_schema_matches`), antes de qualquer
`INSERT`, o job compara a lista de colunas do DataFrame com a da tabela Iceberg
existente e, se divergirem, levanta erro dizendo **qual** é a lista de cada lado.

A força que decide é a primeira: o valor está em encurtar a distância entre a
mudança e o sintoma. As duas camadas transformam "número errado no dashboard na
semana que vem" em "job falhou agora, com as duas listas de colunas impressas".

A opção 2 não foi descartada por ser ruim — evolução de schema é o
comportamento correto quando a mudança é aditiva e **esperada**. Ela foi
descartada porque aqui a mudança nunca é esperada: não há contrato com a origem
que diga o que pode mudar.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Coluna nova na origem é ignorada em silêncio | **Não é contornado.** O `select` fixo protege contra o inesperado e esconde o que talvez fosse desejado |
| `cast` devolve `null` em vez de erro quando o valor não cabe no tipo | Coberto pelo portão de Data Quality ([0005](./0005-onde-fica-o-portao-de-qualidade.md)), que valida valor — é por isso que schema e valor são checagens separadas |
| O contrato mora num dicionário Python, não num registro | Aceito por ora; o item 10 da Fase 04 do TODO (`contracts/*.yml` + CI) é a forma certa |
| Acrescentar coluna exige deploy | Aceito deliberadamente: é o atrito que garante que alguém olhe |

## Quando esta decisão se inverte

- **Quando existir um contrato de dados de verdade com a origem** — schema,
  frescor e dono declarados, com CI que quebra quando a origem muda sem avisar
  (item 10 da Fase 04 do TODO). Aí a evolução aditiva pode ser aceita
  automaticamente, porque passa a existir quem garanta que ela é aditiva. Hoje o
  contrato mora implícito num dicionário Python, o que é melhor que nada e pior
  que um contrato.
- **Quando o número de tabelas crescer.** Declarar 16 colunas à mão para uma
  tabela é razoável; para cinquenta tabelas vira código repetido e desatualizado.
  O gatilho é a terceira ou quarta tabela — aí o schema deve vir de um registro
  (Schema Registry, arquivo de contrato), não do corpo do job.
- **Se a origem passar a ter mudança aditiva frequente e legítima**, o `select`
  fixo vira atrito puro: toda coluna nova exige deploy. Nesse regime, aceitar
  aditivo e rejeitar destrutivo é o meio-termo correto.

## Consequências

- Mudança destrutiva na origem falha na primeira execução, com mensagem que
  nomeia as colunas divergentes dos dois lados — a distância entre causa e
  sintoma cai de semanas para segundos.
- O contrato cobre **nome e tipo da coluna, não a validade do valor**. São duas
  checagens com naturezas diferentes, e é por isso que o portão de qualidade
  existe separado: uma protege a forma, a outra o conteúdo.
- A pipeline passa a ter uma declaração explícita do que espera da origem. Hoje
  ela mora no corpo de um job; ainda não é um contrato publicado, que é o que o
  item 10 da Fase 04 do TODO prevê.

## Evidência no repo

- `workloads/amazonsales/aws/scripts/dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py:7-26`
  — o dicionário `COLUMN_TYPES`, com o comentário que dá o motivo: "inferir do
  Parquet faz o schema da tabela Iceberg mudar sozinho quando a origem muda".
- `workloads/amazonsales/aws/scripts/dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py:29-32`
  — o `cast` seguido de `select` apenas das colunas declaradas.
- `workloads/amazonsales/aws/scripts/glue_common.py:66-82` — o
  `assert_schema_matches`, com o motivo do erro legível.
- `workloads/amazonsales/aws/scripts/glue_common.py:57-64` — o
  `CREATE TABLE IF NOT EXISTS` que a checagem existe para compensar.
