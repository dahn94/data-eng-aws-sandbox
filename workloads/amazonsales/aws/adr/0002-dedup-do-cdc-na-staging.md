# 0002 — Como escolher uma linha por chave quando o CDC entrega várias

**Status:** Aceito — reconhecidamente provisório
**Data do registro:** 2026-08-28

## Contexto e problema

O DMS grava no S3 cada mudança que acontece no Postgres. Um produto editado três
vezes vira três linhas no Parquet, com a mesma chave primária. A camada de
staging precisa entregar **uma linha por chave** para que as dimensões e os fatos
façam sentido.

A pergunta é: **qual das três?** A resposta correta é "a mais recente" — e
descobrir qual é a mais recente exige um critério de ordenação que venha com o
dado.

**Premissa que a decisão atual assume, e que é falsa em produção:** que as
versões de uma mesma chave são equivalentes, ou que a mais recente é a que o
Spark vai devolver. Nenhuma das duas se sustenta.

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Coluna de operação (I/U/D) no arquivo | **ausente** | [`dms/nfr.md`](../../../dms/aws/nfr.md) |
| Timestamp de commit / LSN no arquivo | **ausente** | [`dms/nfr.md`](../../../dms/aws/nfr.md) |
| Ordenação entre eventos da mesma chave | **não preservada** | [`dms/nfr.md`](../../../dms/aws/nfr.md) |
| Consumidor em produção | nenhum | [`nfr.md`](../nfr.md) |
| Volume por carga | não medido | [`nfr.md`](../nfr.md) |

A primeira linha é a que decide tudo, e ela **não é uma escolha desta pipeline**:
é uma propriedade do que o módulo `dms` grava. Sem coluna de operação e sem
timestamp, nenhuma estratégia correta de deduplicação é implementável aqui,
porque o dado necessário para ordenar não chegou.

## Opções consideradas

1. **`dropDuplicates` pela chave primária.** Uma linha por chave, escolhida
   arbitrariamente entre as versões. Implementável com o dado disponível.
2. **Ordenar por timestamp de commit e ficar com a última** (window function
   `row_number()` particionada pela chave). É a resposta correta —
   e **não implementável hoje**: a coluna não existe no arquivo.
3. **Tratar delete como delete**, aplicando `MERGE ... WHEN MATCHED THEN DELETE`
   quando a operação for `D`. Também **não implementável**: não há coluna de
   operação, então um delete é indistinguível de um insert.
4. **Não deduplicar** e deixar a duplicata chegar às dimensões. Rejeitado: o
   `.distinct()` das dimensões esconderia o problema, e os fatos somariam a mesma
   venda mais de uma vez.

## Decisão

Opção 1: `dropDuplicates([primary_key])` na staging, seguido de `MERGE` por
chave na tabela Iceberg.

O requisito que decide é a ausência de coluna de operação e de timestamp na
origem. As opções 2 e 3 não perderam uma comparação — elas não estavam
disponíveis. Isto é uma decisão **restrita pela ingestão**, não uma escolha entre
alternativas equivalentes, e registrá-la assim é o ponto deste ADR.

O que fica aceito, explicitamente:

- **Um update perdido.** Entre duas versões da mesma chave, a que sobrevive é
  arbitrária. Se a antiga vencer, a tabela fica com dado velho, sem sinal nenhum.
- **Um delete que não apaga.** A linha excluída na origem continua na staging
  para sempre, porque chega como mais uma linha e o `MERGE` só faz insert e
  update.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Versão arbitrária vence | **Não é contornado.** Risco aceito enquanto não houver consumidor em produção — a linha "consumidor: nenhum" do `nfr.md` é o que sustenta isso |
| Delete não propaga | **Não é contornado.** Um `DELETE` na origem fica invisível na camada analítica |
| Dado velho passar despercebido | Parcialmente: o portão de Data Quality ([0005](./0005-onde-fica-o-portao-de-qualidade.md)) pega valor fora de faixa, mas não pega "valor válido, porém desatualizado" |
| Full refresh das dims mascarar o problema | Não mascara, mas também não denuncia: a dimensão é reconstruída da staging, então herda o erro dela |

Duas das quatro linhas são "não é contornado". Isso é o registro honesto de um
risco aceito, e é a informação mais útil deste ADR.

## Quando esta decisão se inverte

**Assim que o módulo `dms` passar a gravar coluna de operação e timestamp de
commit.** Não é um gatilho de escala — é um gatilho de capacidade, e depende de
uma mudança de uma linha em `../../../platform/aws/modules/dms/main.tf` (`include_op_for_full_load` e
`timestamp_column_name` no bloco `s3_settings`). No instante em que essas colunas
existirem, a opção 2 vira implementável e esta decisão está obsoleta.

Esse é exatamente o pré-requisito do item 1 da Fase 01 do TODO (MERGE do CDC com
SCD2), e a razão de ele não poder começar pela pipeline: **o trabalho começa na
ingestão, não no processamento.**

Antes disso, dois gatilhos menores tornam o risco intolerável:
- **quando existir um consumidor em produção** da camada analítica;
- **quando a origem passar a ter deletes de verdade** — hoje o
  `workloads/webevents-streaming/seed` só insere, o que torna o problema teórico.

## Consequências

- A pipeline funciona ponta a ponta com o dado que existe, o que permitiu tudo o
  que veio depois dela.
- A camada analítica **não é uma réplica fiel** da origem, e nada no sistema
  comunica isso a quem consulta.
- O erro é silencioso por construção: não há contagem de duplicatas descartadas,
  nem log de quantas versões existiam por chave. Instrumentar isso seria a
  melhoria mais barata deste ADR — uma contagem antes e depois do
  `dropDuplicates` já daria visibilidade.
- A staging usa `MERGE` (incremental) enquanto dimensões e fatos usam full
  refresh. Os motivos são diferentes e estão em
  [0004](./0004-politica-de-recarga-por-camada.md).

## Evidência no repo

- `workloads/amazonsales/aws/scripts/dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py:43`
  — o `dropDuplicates([primary_key])`, sem ordenação.
- `workloads/amazonsales/aws/scripts/dataeng-sandbox-amazonsales-dw-table-stg-s3tables.py:45`
  — o `merge_table` que grava a staging.
- `workloads/amazonsales/aws/scripts/glue_common.py:99-122` — o `MERGE`,
  que tem `WHEN MATCHED THEN UPDATE` e `WHEN NOT MATCHED THEN INSERT`, e
  **nenhuma** cláusula de delete.
- `../../../../platform/aws/modules/dms/main.tf:111-117` — o `s3_settings` sem
  `include_op_for_full_load` nem `timestamp_column_name`: a causa raiz.
