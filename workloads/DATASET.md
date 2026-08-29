# Contrato de dataset

Cada workload deste diretório é dono da própria infraestrutura — inclusive
quando isso significa quatro Redshifts separados. Essa escolha custa uma coisa:
**os números de um workload não são comparáveis com os de outro por construção.**

Este documento é o que devolve a comparação. Se todos lerem o mesmo dado, com o
mesmo schema, na mesma janela, então latência, custo e bytes escaneados voltam a
significar alguma coisa quando colocados lado a lado — e os ADRs param de ser
opinião.

O que garante a comparação não é infraestrutura compartilhada. É **dado
idêntico**.

## Versão vigente

**`v1`** — declarada em 2026-08-29. Todo `nfr.md` que reporta número medido deve
citar a versão do dataset sobre a qual mediu. Número sem versão não entra na
comparação.

## O schema

Uma tabela de vendas, deliberadamente pequena e sem surpresa. Ela existe nos
quatro lugares com o mesmo formato:

| Coluna | Tipo | Observação |
|---|---|---|
| `order_id` | `BIGINT` | chave do pedido |
| `customer_id` | `BIGINT` | chave de distribuição no Redshift |
| `pedido_em` | `TIMESTAMP` | chave de ordenação; é a coluna que a MV agrupa |
| `valor` | `DECIMAL(12,2)` | |
| `status` | `VARCHAR(32)` | |

No Postgres de origem de cada workload ela é a tabela transacional; no lake é parquet;
no Redshift ela é tabela local. O tipo muda de nome conforme o motor, o
significado não.

## A janela

| Parâmetro | Valor `v1` |
|---|---|
| Início | `2026-01-01T00:00:00Z` |
| Fim | `2026-03-31T23:59:59Z` |
| Linhas | **1.000.000** |
| Clientes distintos | 50.000 |
| Distribuição no tempo | uniforme por hora, com pico 3× entre 18h e 22h |

O pico existe de propósito: sem ele, `DATE_TRUNC('hour', ...)` produz grupos
todos do mesmo tamanho e a materialized view do `incremental-mv` fica com um
desempenho artificialmente bom.

## Onde o dado mora

```
s3://<seu-prefixo>-lake-raw/datasets/vendas/    # parquet, particionado por dia
```

É esse caminho que `seed_bucket` + `seed_prefix` apontam nos
`envs/*.tfvars` do `incremental-mv` e do `data-sharing`. Os dois sobem sem ele
(tabela vazia, tudo funciona, nada é comparável).

## O que todo `nfr.md` registra

Estas quatro linhas são o mínimo para um workload entrar na comparação:

| Métrica | Como medir |
|---|---|
| Latência p50 e p95 | a **mesma** query de negócio, 20 execuções, cache frio |
| Bytes escaneados | Athena: console; Redshift: `SVL_QUERY_METRICS` |
| Defasagem do dado | diferença entre `MAX(pedido_em)` na origem e no destino |
| Custo da execução | workgroup próprio por workload — é para isso que ele existe |

A query de negócio de referência, igual para todos:

```sql
SELECT DATE_TRUNC('hour', pedido_em) AS hora,
       COUNT(*)                      AS pedidos,
       SUM(valor)                    AS receita
  FROM vendas
 WHERE pedido_em >= '2026-03-01'
 GROUP BY 1
 ORDER BY 1;
```

## O que ainda falta para este contrato valer

Ser honesto sobre isto importa mais do que o contrato parecer pronto:

- [ ] **O gerador não é determinístico.**
      `local-services/data-generator/script-insert-postgres-webfake-events.py`
      não aceita `--seed` nem janela por parâmetro: hoje ele gera eventos web
      contínuos, não a tabela de vendas descrita aqui. Enquanto isso não
      existir, duas execuções produzem dados diferentes e **a comparação não é
      reproduzível por terceiros** — só dentro de uma mesma rodada sua.
- [ ] **Ninguém publica o parquet em `datasets/vendas/`.** O caminho está
      declarado, o produtor dele não existe. Por isso `seed_bucket` nasce vazio
      nos `envs/*.tfvars`.
- [ ] **Nenhum número foi medido ainda.** Todos os `nfr.md` dos workloads novos
      têm as linhas de latência e custo marcadas como *não medido*. Isso é
      intencional: campo vazio é honesto, campo chutado contamina os ADRs que
      dependem dele.

Enquanto esses três itens estiverem abertos, este documento é um **contrato
declarado, não um contrato exercido**. Os ADRs que dependem de número medido
dizem isso explicitamente na seção de premissas.
