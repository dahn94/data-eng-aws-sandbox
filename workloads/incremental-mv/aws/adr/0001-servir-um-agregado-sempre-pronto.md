# 0001 — Como servir um agregado sempre pronto sem virar dono do agendamento

**Status:** Aceito
**Data do registro:** 2026-08-29

## Contexto e problema

Um dashboard de receita por hora leva 40 segundos para abrir e é aberto cerca de
200 vezes por dia. Toda abertura recomputa o mesmo `GROUP BY` sobre as mesmas
linhas — e quase toda a base é de ontem, imutável. O trabalho é repetido por
construção.

O problema declarado é latência de leitura. O problema real é **trabalho
repetido**: o mesmo resultado é calculado 200 vezes porque não foi guardado em
lugar nenhum.

Guardar o resultado é a resposta óbvia. A pergunta deste ADR é **quem decide o
momento de recalcular** — porque essa é a única variável que separa as opções
disponíveis, e é a que gera trabalho operacional para sempre.

**Premissas que esta decisão assume:**

1. **Não há SLA de frescor.** O consumo é um dashboard de análise, não uma tela
   operacional. Assumido a partir do caso, **não confirmado com quem consome**.
   Se houver SLA, a decisão cai — auto refresh não promete intervalo.
2. **A base muda pouco em relação ao total.** É o que torna o refresh incremental
   barato. Verdadeiro para dado histórico agregado por hora; falso para uma
   tabela reescrita inteira a cada carga.
3. **O agregado cabe no SQL que o auto refresh suporta.** Verdadeiro hoje
   (`SUM`, `COUNT`, `GROUP BY`), com margem **não avaliada** para crescer.
4. **O custo de um Redshift ligado é aceitável.** Assumido, **não medido** — a
   tabela de custo do [`nfr.md`](../nfr.md) está vazia.

## Requisitos que decidem

| Requisito | Valor exigido | Origem |
|---|---|---|
| Latência na leitura | < 2 s | [`nfr.md`](../nfr.md) — "A pergunta que este caminho responde" |
| Frequência da leitura | ~200×/dia | [`nfr.md`](../nfr.md) |
| Defasagem tolerada | minutos, **sem garantia contratual** | [`nfr.md`](../nfr.md) |
| Fração da base que muda | pequena | [`nfr.md`](../nfr.md) |
| Código próprio a operar | 0 linhas | [`nfr.md`](../nfr.md) — "Execução" |
| Complexidade do agregado | `GROUP BY` simples | [`nfr.md`](../nfr.md) — "Restrições do mecanismo" |

**"Defasagem tolerada sem garantia contratual" é o requisito que decide.** Ele é
o único que separa a materialized view de um job agendado: as duas entregam
latência baixa; só uma exige que ninguém prometa frescor.

## Opções consideradas

1. **Cache no BI.** Mais barato de todos, e resolve a latência. Rejeitado
   porque o cache é por ferramenta: outra ferramenta, outro cache, e a
   inconsistência entre elas vira chamado. O agregado precisa existir no dado,
   não na tela.
2. **Job agendado que materializa a tabela** (Glue ou Step Functions, que o
   repositório já sabe operar). Entrega latência baixa e frescor previsível.
   Rejeitado pelo que cobra: dono do intervalo, do incremental, do retry e do
   backfill — quatro problemas operacionais para um agregado de duas linhas de
   SQL.
3. **Materialized view com `AUTO REFRESH YES`.** Declarativa, incremental por
   construção, mantida pelo motor. Custa não poder prometer frescor.
4. **Materialized view com refresh manual.** O meio-termo: incremental de graça,
   mas o "quando" volta a ser seu. É a opção 2 com menos código — e mantém todos
   os problemas operacionais dela.

## Decisão

Opção 3: materialized view com auto refresh, num Redshift Serverless próprio
deste workload.

Decidiu **defasagem sem garantia contratual**. Sem ninguém para prometer frescor,
a única diferença que sobra entre as opções 2, 3 e 4 é quanta operação cada uma
gera — e a 3 gera nenhuma.

Entre 3 e 4, a escolha é reversível: `mv_auto_refresh = false` no
`envs/*.tfvars` devolve o agendamento para você. A variável existe justamente
para que a comparação seja executável e não teórica.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Sem SLA de frescor | **Não é contornado.** É a contrapartida da decisão. O que existe é observabilidade: `SVL_MV_REFRESH_STATUS` mostra cada refresh e o tipo, e o `output check_refresh_query` entrega a consulta pronta. |
| Custo de refresh sem consulta | Capacidade no mínimo (4 RPU) e teardown ao fim da sessão. Trata o sintoma; o custo segue **não medido**. |
| Restrição de SQL do auto refresh | Não é contornado. Se o agregado crescer além do subconjunto suportado, o caminho acaba — e a opção 2 volta, com motivo. |
| Terraform não reconcilia a definição da view | Não é contornado. `aws_redshiftdata_statement` roda uma vez, na criação; alterar a view é `DROP` + `CREATE` manual. A alternativa seria um provider de SQL mantendo estado de banco, o que troca um limite conhecido por uma dependência frágil. |
| A tabela base sobe vazia por padrão | `seed_bucket` semeia a partir do lake quando você quiser volume. Vazio por default de propósito: o parquet de `datasets/vendas/` ainda não é publicado por ninguém — ver [`../../DATASET.md`](../../../DATASET.md). |

## Quando esta decisão se inverte

- **Quando alguém exigir frescor com número.** "Nunca mais de 5 minutos" é um
  requisito que o auto refresh não atende. Aí a opção 2 volta, e o custo
  operacional dela passa a ser justificado.
- **Quando o agregado sair do SQL suportado.** Restrição do serviço, não
  negociável.
- **Quando a base passar a mudar quase inteira a cada carga.** O refresh
  incremental deixa de ser barato, e materializar perde para recomputar.
- **Quando o custo dos refreshes automáticos for medido e passar do de um cron.**
  Hoje é palpite dos dois lados.

## Consequências

O repositório passou a ter um caminho onde **o momento da computação não é
decisão de engenharia** — e é o único assim. Nos outros, alguém escolheu uma
frequência: o `../amazonsales/` roda quando disparado, o `../webevents-streaming/`
roda contínuo, o `../dms/` roda por evento. Aqui ninguém escolheu.

Passou a existir o segundo workload cujo custo não cai a zero sem uso (o
primeiro é o `../zero-etl/`). Isso consolida um eixo de custo novo no
repositório: serviços que cobram por existir, ao lado dos que cobram por
execução.

A variável `mv_auto_refresh` torna a comparação "motor decide × você decide"
executável dentro da mesma pasta, sem infraestrutura nova.

## Evidência no repo

- **Mecanismo verificado em execução (2026-08-29)**, em `local/` com ClickHouse:
  depois de três inserções o agregado da hora 10 marcava 2 pedidos e 250; uma
  quarta inserção o levou a 3 e 350, sem nenhum refresh pedido. Não é Redshift —
  o ClickHouse atualiza na escrita, e o Redshift decide o momento — mas a
  propriedade que este ADR defende, *ninguém agenda recomputação*, é a mesma.

- `workloads/incremental-mv/aws/infra/main.tf:212-233` — a view e as duas palavras que
  transferem o "quando" para o motor.
- `workloads/incremental-mv/aws/infra/main.tf:175-184` — a tabela base, com `DISTKEY` e
  `SORTKEY` escolhidos para o agregado por hora.
- `workloads/incremental-mv/aws/infra/main.tf:165-168` — o comentário que registra a
  fronteira do IaC: SQL executado na criação, não reconciliado.
- `workloads/incremental-mv/aws/infra/outputs.tf` — `check_refresh_query`, a consulta que
  prova que o refresh aconteceu sem pedido.
- `workloads/incremental-mv/aws/infra/variables.tf` — `mv_auto_refresh`, a chave que
  inverte a decisão para efeito de comparação.
