# 0001 — Como responder uma pergunta sobre o estado de agora

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

Existe uma classe de pergunta que o lakehouse não responde: a que é sobre o
**estado do instante**. "Este pedido, agora, está com que status?" — feita
enquanto alguém decide segurar ou liberar uma transação, sobre uma linha que
mudou há quatro minutos.

Toda cópia tem defasagem. A carga batch roda de hora em hora, e mesmo apertada
para cinco minutos continuaria sem garantir que a linha de quatro minutos atrás
esteja lá. O problema não é a frequência da carga: é que **a pergunta é sobre
um estado que só a fonte conhece**.

Some-se a isso a frequência: a pergunta aparece cerca de três vezes por semana,
sob demanda, sem horário.

**Premissas que esta decisão assume:**

1. **A consulta é seletiva** — filtro por chave primária, devolvendo dezenas de
   linhas, não varredura de tabela.
2. **A fonte aguenta a carga adicional.** Assumido, **não medido** — as três
   linhas de impacto na fonte no [`nfr.md`](../nfr.md) estão vazias. Se for
   falsa, esta decisão cai.
3. **A pergunta não precisa de histórico.** Ler o estado atual basta; o valor
   anterior não é necessário.

## Requisitos que decidem

| Requisito | Valor exigido | Origem |
|---|---|---|
| Defasagem tolerada | **zero** | [`nfr.md`](../nfr.md) — "A pergunta que este caminho responde" |
| Frequência da pergunta | ~3× por semana, sob demanda | [`nfr.md`](../nfr.md) |
| Histórico exigido | nenhum | [`nfr.md`](../nfr.md) |
| Seletividade | alta — filtro por chave | [`nfr.md`](../nfr.md) |
| Volume por consulta | dezenas a centenas de linhas | [`nfr.md`](../nfr.md) |
| Impacto aceitável na fonte | **não declarado** | [`nfr.md`](../nfr.md) — "Impacto na fonte" |
| Custo de ingestão | US$0 exigido para o caso se pagar | [`nfr.md`](../nfr.md) — "Custo" |

**Defasagem zero é o requisito que decide**, e ele elimina toda a família de
opções que copiam dado — independentemente de quão rápido copiem.

## Opções consideradas

1. **Apertar a janela do pipeline batch** para 5 minutos. Não resolve: a linha
   de 4 minutos atrás pode não ter entrado. Reduz a defasagem, não a elimina, e
   o requisito é *zero*. Além disso, faz o custo e a operação subirem 12× para
   atender três perguntas por semana.
2. **CDC contínuo para o lake** (o `dms/` já existente) e consultar o lake.
   Defasagem menor, mas ainda existente — e propagar até uma tabela consultável
   envolve `MERGE`, que é justamente o que ainda não existe aqui.
3. **Federar: consultar o Postgres de dentro do Athena**, sem cópia. Defasagem
   zero por construção — a leitura acontece na fonte, no instante da pergunta.
4. **Dar acesso de leitura direto no Postgres para a analista.** Também tem
   defasagem zero, e é mais simples. Rejeitado por dois motivos: não permite
   `JOIN` com o histórico que está no lake — que é metade da pergunta — e
   distribui credencial de banco de produção para fora do time de dados.

## Decisão

Opção 3: catálogo federado no Athena, com conector Lambda dentro da VPC.

O requisito que pesou foi **defasagem tolerada = zero**, que sozinho descarta as
opções 1 e 2. Entre 3 e 4, decidiu a necessidade de `JOIN` com o histórico do
lake na mesma query: a opção 4 responde metade da pergunta.

A frequência baixa (3×/semana) é o que torna a escolha **proporcional**: não se
constrói nem se opera nada, e o custo parado é US$0. Se a frequência subisse
para contínua, a conta mudaria de lado — ver "Quando esta decisão se inverte".

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| A query bate no banco de produção | **Não é contornado.** É um risco aceito, e o `nfr.md` registra que o impacto nunca foi medido. Esta é a fragilidade principal da decisão. |
| Latência imprevisível — depende da saúde do OLTP | Não é contornado. Aceitável porque o consumo é humano e sob demanda, não um dashboard com SLA. |
| Sem histórico: `UPDATE` in-place apaga o passado | Não é contornado aqui, e nem deveria ser — é papel do `dms/` e do lake. Este caminho é complementar a eles, não substituto. |
| Resultado grande estoura o payload da Lambda | Spill para S3, com expiração em 3 dias (`../main.tf:63-77`). Trata o sintoma; a premissa de seletividade é o que evita o caso. |
| Credencial do Postgres num segundo lugar | Vai para o Secrets Manager e é lida em runtime pela Lambda — não fica no state nem como argumento (`../main.tf:96-110`). |
| Conector é aplicação de terceiro, instalada do SAR | Não é contornado. A alternativa seria manter build próprio de um jar da AWS, o que troca um risco por um custo de manutenção maior. |

## Quando esta decisão se inverte

- **Quando a pergunta virar rotina.** Passando de ~3 por semana para dezenas por
  dia, o custo por consulta e a carga acumulada na fonte superam o custo de
  construir e operar um caminho materializado. O gatilho é a linha "frequência
  da pergunta" do `nfr.md`.
- **Quando o impacto na fonte for medido e passar do aceitável.** Hoje o teto
  nem existe ("não declarado"). Declarar esse número — e medir o aumento de CPU
  do RDS durante a query — é a tarefa que valida ou derruba esta decisão.
- **Quando a consulta deixar de ser seletiva.** Se o caso de uso passar a exigir
  varredura ou agregação sobre a tabela toda, federar vira o pior caminho:
  lento, com spill, e pesado para o OLTP.
- **Quando a pergunta passar a exigir o valor anterior.** Aí não é mais sobre o
  estado de agora, e nenhuma federação responde.

## Consequências

O repositório passou a ter um caminho até o analytics **sem pipeline** — e é a
primeira vez que isso é verdade aqui. O `README.md` da raiz reorganizou a
taxonomia por causa disso.

Passou a existir carga analítica sobre o banco transacional, sem teto declarado
e sem medição. Isso é pior do que antes e **não tem mitigação hoje**.

O `sources/rds` passou a exportar `security_group_id` para que o consumidor
declare a própria regra de entrada, em vez de o RDS conhecer seus consumidores.
Isso inverte a direção do acoplamento e vale para os próximos workloads.

## Evidência no repo

- `workloads/federated-query/main.tf:152-178` — o conector instalado do
  Serverless Application Repository, dentro da VPC, em subnet privada.
- `workloads/federated-query/main.tf:186-194` — o catálogo `LAMBDA` que faz o
  Postgres aparecer como fonte dentro do Athena.
- `workloads/federated-query/main.tf:196-215` — o workgroup próprio, que existe
  para isolar o custo deste caminho e permitir a comparação.
- `workloads/federated-query/main.tf:96-110` — a credencial no Secrets Manager.
- `workloads/federated-query/main.tf:136-143` — a regra de entrada no RDS
  declarada pelo consumidor.
- `sources/rds/outputs.tf` — o `security_group_id` exportado para isso.
