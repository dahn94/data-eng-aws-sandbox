# 0001 — Como manter uma cópia fiel do OLTP sem virar dono do transporte

**Status:** Aceito
**Data do registro:** 2026-08-29

## Contexto e problema

Existe uma classe de pedido que não é uma pergunta de negócio: *"preciso das
tabelas do sistema no warehouse, todas, atualizadas"*. Não há regra de negócio a
aplicar, não há modelagem a fazer, não há transformação pedida. O que se pede é
que a tabela exista no lugar onde o analista já sabe consultar.

O repositório já responde isso duas vezes por caminho próprio — o `../dms/`
captura mudança linha a linha e o `../amazonsales/` transforma e modela. Ambos
funcionam. Ambos fazem de alguém o dono do transporte: do `MERGE` incremental,
da evolução de schema, do retry, do alerta.

A pergunta deste ADR é se **ser dono do transporte se justifica quando o pedido
não inclui transformação nenhuma**.

**Premissas que esta decisão assume:**

1. **Não há transformação no caminho.** Se houver, a decisão cai imediatamente —
   a integração gerenciada não tem onde colocar regra de negócio.
2. **Defasagem de minutos é aceitável.** Assumido a partir do pedido, **não
   negociado com quem pediu**. Se o requisito real for segundos, ver
   `../federated-query/`; se for horas, um batch é mais barato.
3. **O custo de um Redshift ligado é aceitável para o caso.** Assumido, **não
   medido** — a tabela de custo do [`nfr.md`](../nfr.md) está vazia. Esta é a
   premissa mais frágil das três.
4. **A origem continua em PostgreSQL ≥ 15.4.** Hoje é PG 17. Um downgrade ou uma
   troca de motor invalida o caminho inteiro.

## Requisitos que decidem

| Requisito | Valor exigido | Origem |
|---|---|---|
| Transformação exigida | **nenhuma** | [`nfr.md`](../nfr.md) — "A pergunta que este caminho responde" |
| Defasagem tolerada | minutos | [`nfr.md`](../nfr.md) |
| Escopo | banco inteiro, não uma tabela | [`nfr.md`](../nfr.md) |
| Código próprio a operar | **0 linhas** | [`nfr.md`](../nfr.md) — "Execução" |
| Histórico exigido no destino | nenhum | [`nfr.md`](../nfr.md) |
| Custo do destino parado | **não medido** | [`nfr.md`](../nfr.md) — "Custo" |

**Transformação = nenhuma é o requisito que decide.** Ele é o único que torna
legítimo abrir mão de um pipeline: sem lugar para colocar regra de negócio, um
pipeline seria só encanamento caro.

## Opções consideradas

1. **Estender o `../dms/`** para replicar o banco inteiro e materializar no lake.
   Já existe, já funciona, e não custa Redshift ligado. Rejeitado porque o
   trabalho caro — `MERGE` incremental idempotente, com deleção e
   reprocessamento — continua sendo nosso, para entregar exatamente o que a
   integração gerenciada entrega de graça.
2. **Um pipeline batch de `full load` periódico.** Simples e barato. Rejeitado
   pela defasagem: recarregar o banco inteiro de hora em hora não escala e ainda
   assim entrega dado velho.
3. **Integração zero-ETL RDS → Redshift.** Declarativa, mantida pela AWS, sem
   código. Custa um warehouse ligado.
4. **Federar** (`../federated-query/`). Defasagem zero e custo parado zero.
   Rejeitado para *este* pedido: o escopo é o banco inteiro, em uso repetido por
   analistas — exatamente o padrão de carga que a federação não aguenta, e que o
   ADR daquele workload declara como gatilho de inversão.

## Decisão

Opção 3: integração gerenciada RDS → Redshift Serverless, com o warehouse
pertencendo a este workload.

Decidiu **transformação = nenhuma**, combinada com **código próprio = 0 linhas**.
Entre 1 e 3, a diferença não é capacidade — as duas entregam a tabela no destino
— é quem carrega o transporte. Quando não há transformação a fazer, carregar o
transporte é custo puro.

O warehouse é criado por este workload, e não compartilhado, por decisão de
projeto do repositório: cada pasta sobe sozinha com um comando. O custo dessa
escolha é duplicação de infraestrutura, não de código — o Redshift vem de
`../../modules/redshift-serverless`, instanciado também pelo `../incremental-mv/`
e pelo `../data-sharing/`.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Custo do Redshift ligado | Capacidade no mínimo do serviço (4 RPU) e `terraform destroy` ao fim da sessão, com o `scripts/teardown.sh` conhecendo a ordem. Trata o sintoma; o custo por hora segue **não medido**. |
| Sem transformação no caminho | **Não é contornado.** É a premissa da decisão, não um efeito colateral. Transformar exige outro caminho. |
| Sem histórico no destino | Não é contornado aqui, e nem deveria ser: histórico é papel do `../dms/` e do lake. Os dois caminhos coexistem de propósito. |
| Acoplamento ao schema da origem | Filtro por `source_tables` limita a superfície (`envs/*.tfvars`), mas renomear coluna na origem continua atravessando até o dashboard, sem aviso. |
| Acúmulo de WAL se o destino parar | **Não é contornado.** Numa `db.t4g.micro` o disco enche rápido. O `nfr.md` registra o risco como não medido. |
| Passo manual de `CREATE DATABASE` | Não é contornado — não há recurso Terraform para ele. O `output next_step` entrega o comando pronto, com o ID da integração já substituído. |

## Quando esta decisão se inverte

- **No primeiro pedido de transformação.** "Renomeia essa coluna", "junta essas
  duas tabelas", "aplica a regra de negócio X" — qualquer um derruba a premissa
  1, e a resposta volta a ser pipeline.
- **Quando o custo do warehouse parado for medido e passar do orçamento.** O
  `README.md` da raiz promete "alguns dólares por sessão". Se a medição
  contradisser, este é o primeiro workload a sair.
- **Quando a origem deixar de ser PostgreSQL ≥ 15.4.** Restrição do serviço, não
  negociável.
- **Quando alguém precisar do valor anterior.** Não é mais o mesmo problema, e
  nenhuma replicação fiel responde.

## Consequências

O repositório passou a ter **dois caminhos resolvendo o mesmo transporte** —
este e o `../dms/` — de propósito. Eles não são redundantes: um entrega o estado
atual sem trabalho nenhum, o outro entrega o passado ao custo de trabalho. Ter os
dois lado a lado, sobre o mesmo dado, é o experimento.

O `sources/rds` passou a exportar `db_instance_arn` para que este workload cite
a origem por ARN.

Passou a existir infraestrutura cujo custo **não cai a zero quando ninguém usa** —
o primeiro caso no repositório. Isso muda a disciplina de teardown de
"recomendável" para "necessário", e é a razão de o `scripts/teardown.sh` colocar
os workloads de Redshift antes do `sources/rds`.

## Evidência no repo

- `workloads/zero-etl/main.tf:123-133` — a integração inteira: origem, destino,
  filtro. Nenhum código de transporte.
- `workloads/zero-etl/main.tf:96-119` — a resource policy no destino, sem a qual
  a integração falha com erro que não aponta para o lado do Redshift.
- `workloads/zero-etl/main.tf:86` — `case_sensitive_identifier = true`, exigido
  porque a integração replica os nomes da origem como eles são.
- `workloads/zero-etl/outputs.tf` — o `next_step`, que é a fronteira honesta do
  Terraform aqui.
- `sources/rds/outputs.tf` — o `db_instance_arn` exportado para isto.
