# 0001 — Como dar semântica de tabela a arquivos soltos no S3

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

A saída da captura de mudanças é um monte de arquivo Parquet no S3. Para
qualquer análise além de "ler tudo de novo", esses arquivos precisam se comportar
como tabela: aplicar `UPDATE`/`DELETE` linha a linha, ler um estado consistente
enquanto uma escrita acontece, e voltar no tempo quando um job gravar errado.

Parquet sozinho não dá nada disso — é formato de arquivo, não de tabela. Falta
uma camada de metadados que diga quais arquivos compõem a tabela agora.

O repo precisa dessa camada porque o alvo é um star schema com dimensões
atualizáveis (o `merge_table` do `glue_common`) e porque a Fase 01 do TODO
depende de `MERGE INTO` e de SCD Tipo 2 sobre CDC.

## Requisitos que decidem

| Requisito | Valor exigido | Origem |
|---|---|---|
| Motores que leem as mesmas tabelas | **3** — Spark (Glue), DuckDB (Lambda), Athena | [`query-lambda/nfr.md`](../../../workloads/query-lambda/nfr.md) |
| `UPDATE`/`DELETE` por linha | exigido — a staging faz upsert por chave | [`amazonsales/nfr.md`](../../../workloads/amazonsales/nfr.md) |
| Leitura consistente durante escrita | exigida — dims e fatos usam `INSERT OVERWRITE` | [`amazonsales/adr/0004`](../../../workloads/amazonsales/adr/0004-politica-de-recarga-por-camada.md) |
| Recuperação de escrita errada | time travel por snapshot | [`amazonsales/nfr.md`](../../../workloads/amazonsales/nfr.md) |
| Catálogo a operar | **nenhum** | premissa do repo |
| Custo parado | US$0 fixo | `../README.md:56-58` |

O requisito que decide é o primeiro: **quantos motores diferentes leem a mesma
tabela.** Três, de fornecedores distintos, e o item 8 da Fase 04 do TODO prevê
acrescentar Trino e ClickHouse. Um formato que privilegie um motor específico
torna os outros cidadãos de segunda classe.

Os requisitos 2 a 4 são atendidos igualmente bem por qualquer formato de tabela
aberto — eles eliminam Parquet puro, mas não desempatam entre os candidatos.
Quem desempata é o leitor.

## Opções consideradas

1. **Parquet puro com partições no S3.** Zero dependência. Sem transação, sem
   `MERGE`, sem time travel: reescrever partição inteira a cada atualização.
2. **Delta Lake.** Maduro, excelente ferramenta, ecossistema forte — e com o
   melhor suporte dentro do Databricks, que não é o alvo aqui.
3. **Apache Hudi.** Historicamente o mais forte em upsert e ingestão incremental,
   bem integrado ao Glue. Comunidade e ferramental de terceiros menores.
4. **Apache Iceberg**, com os metadados gerenciados pelo **S3 Tables** (o bucket
   `dataeng-sandbox-lakehouse-<amb>`), em vez de um catálogo próprio.

## Decisão

Iceberg sobre S3 Tables.

A força que decide é **quem lê**: Iceberg é o formato com adoção mais ampla e
neutra entre engines — Spark, Athena, Trino, DuckDB, ClickHouse — o que é
exatamente o requisito de um repo cujo próximo item de estudo é comparar quatro
engines de query sobre *as mesmas* tabelas (Fase 04 do TODO). Delta e Hudi
resolveriam `MERGE` e time travel igualmente bem; o que os desempata aqui não é
capacidade, é o leitor.

A segunda escolha, separada da primeira, é **S3 Tables em vez de um catálogo
autogerenciado**: manutenção de tabela (compaction, expiração de snapshot) passa
a ser responsabilidade do serviço e não há metastore para operar, coerente com a
premissa de nada cobrar parado.

Consequência prática do S3 Tables: os jobs precisam do jar
`s3-tables-catalog-for-iceberg-runtime`, e a configuração do catálogo Spark ficou
concentrada numa única função (`create_spark_session`, em `glue_common.py`) —
antes cada um dos oito scripts tinha sua cópia.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Acoplamento ao S3 Tables como catálogo | Parcial: o **formato** (Iceberg) é portável; migrar significa trocar o catálogo, não reescrever o dado |
| Dependência de jar de ~15 MB fora do Git | Contornado: `scripts/fetch-jars.sh` baixa e o Terraform envia ao S3, em vez de upload manual |
| ARN do lakehouse é contrato implícito entre módulos | Contornado por convenção de nome determinística, com variável para sobrescrever |
| Nenhum emulador cobre S3 Tables | **Não é contornado.** O caminho honesto para exercitar a lógica é PySpark local contra MinIO e um catálogo Iceberg — é o que `local-services/` passa a oferecer |
| Manutenção de tabela (arquivos pequenos, snapshots) | Delegada ao serviço hoje; quando não bastar, vira job explícito — item 2 da Fase 01 do TODO |

## Quando esta decisão se inverte

- **Se o processamento migrar para Databricks**, Delta deixa de ser a opção
  estrangeira e vira a nativa; o argumento "quem lê" se inverte inteiro.
- **Se a carga virar ingestão incremental de altíssima frequência com upsert
  pesado**, vale reavaliar Hudi, historicamente mais forte nesse recorte
  específico.
- **Se a manutenção automática do S3 Tables deixar de ser suficiente** — arquivo
  pequeno demais, snapshot acumulando, custo de scan subindo —, a resposta não é
  trocar de formato, é assumir a manutenção explicitamente
  (`rewrite_data_files`, `expire_snapshots`), que é justamente o item 2 da Fase
  01 do TODO. O gatilho observável é o número de arquivos por partição e os
  bytes escaneados pelo Athena na mesma query.
- **Se a manutenção automática do catálogo deixar de bastar** — arquivos
  pequenos demais, snapshots acumulando, bytes escaneados subindo —, a resposta
  não é trocar de formato, é assumir a manutenção (`rewrite_data_files`,
  `expire_snapshots`), que é o item 2 da Fase 01 do TODO. O gatilho observável é
  o número de arquivos por partição, hoje **não medido**.

## Consequências

- `MERGE INTO`, time travel e leitura consistente durante escrita passam a
  existir — é o que permite `merge_table` e o que torna a Fase 01 possível.
- Nasce uma dependência de jar versionado fora do Git (~15 MB), baixado por
  `scripts/fetch-jars.sh` e enviado ao S3 pelo Terraform.
- O ARN do bucket S3 Tables vira contrato entre módulos: criado no `foundation`,
  consumido pelas pipelines por convenção de nome, porque o state local não é
  legível por `terraform_remote_state`.
- Fica um acoplamento a serviço AWS. O formato (Iceberg) é portável; o
  **catálogo** (S3 Tables) não é.

## ⚠️ Inferido

A **decisão** é evidência dura — Iceberg e S3 Tables estão no código. As
**opções consideradas** não são: o repositório nunca menciona Delta, Hudi ou
Parquet puro em lugar nenhum, e o histórico do Git foi consolidado num commit
único. A comparação acima foi reconstruída a partir do que o código exige
(`MERGE`, múltiplos leitores, zero operação) e das propriedades conhecidas de
cada formato — não de um registro de que essas alternativas foram de fato
avaliadas na época. Se a escolha original foi por outro motivo (o curso que
originou o repo, por exemplo), corrija este ADR: o motivo real vale mais do que
a reconstrução coerente.

## Evidência no repo

- `platform/foundation/main.tf:102-105` — a criação do bucket S3 Tables.
- `platform/foundation/README.md:27` — o bucket descrito como "onde as
  tabelas Iceberg vivem".
- `workloads/amazonsales/scripts/glue_common.py:19-45` — a sessão
  Spark com o catálogo Iceberg do S3 Tables, e o comentário de que os nomes de
  tabela são relativos a ele.
- `workloads/amazonsales/scripts/glue_common.py:99-122` — o
  `merge_table`, o upsert que motiva a camada de tabela.
- `workloads/amazonsales/main.tf:40-43` — o jar do catálogo
  enviado pelo Terraform, com o comentário de por que ele vive no repositório.
- `workloads/query-lambda/README.md:3` — DuckDB consultando as mesmas
  tabelas: o segundo leitor que sustenta a força decisiva.
