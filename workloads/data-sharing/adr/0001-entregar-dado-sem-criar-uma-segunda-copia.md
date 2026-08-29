# 0001 — Como entregar dado a outro time sem criar uma segunda cópia

**Status:** Aceito
**Data do registro:** 2026-08-29

## Contexto e problema

O marketing pediu as vendas em CSV, toda segunda. É um pedido trivial de
atender: meia hora de trabalho para um job de export.

O custo não está em atender, está em manter. Um arquivo entregue vira uma
segunda fonte da verdade que diverge da primeira em semanas; envelhece em dias e
não avisa quem o lê; gera um chamado recorrente a cada coluna nova; e transfere
o dado sem transferir a responsabilidade por ele.

O ponto que reenquadra o problema: **o pedido parecia ser sobre transporte, e é
sobre acesso.** "Mandar em CSV" foi o único mecanismo que quem pediu conhecia
para dizer "quero poder olhar as vendas".

**Premissas que esta decisão assume:**

1. **O consumidor usa Redshift, na mesma região.** Verdadeiro no experimento,
   **assumido no caso real**. Se for BigQuery, Excel ou qualquer outra coisa,
   esta decisão não se aplica — e o export volta a ser a resposta certa.
2. **O consumidor pode depender da disponibilidade do produtor.** Sem cópia não
   há autonomia. Assumido, **não negociado** com quem consome.
3. **Não há exigência de mascaramento ou filtro por linha.** O escopo
   compartilhado é objeto inteiro. A PII do escopo **não foi avaliada** — ver
   [`nfr.md`](../nfr.md), seção "Governança".
4. **O custo de dois warehouses ligados é aceitável para o experimento.**
   Assumido, **não medido**.

## Requisitos que decidem

| Requisito | Valor exigido | Origem |
|---|---|---|
| Fontes da verdade aceitas | **uma** | [`nfr.md`](../nfr.md) — "A pergunta que este caminho responde" |
| Defasagem tolerada | zero | [`nfr.md`](../nfr.md) |
| Revogação de acesso | imediata | [`nfr.md`](../nfr.md) — "Governança" |
| Autonomia do consumidor | nenhuma exigida | [`nfr.md`](../nfr.md) |
| Motor do consumidor | Redshift, mesma região | [`nfr.md`](../nfr.md) |
| Código próprio a operar | 0 linhas | [`nfr.md`](../nfr.md) — "Execução" |

**"Uma fonte da verdade" é o requisito que decide**, e ele elimina toda opção que
entregue um artefato — CSV, parquet, tabela replicada. Qualquer cópia entregue é
a segunda fonte, independentemente de com que frequência seja atualizada.

## Opções consideradas

1. **Pipeline de export para CSV/S3.** O pedido literal. Rejeitado pelos quatro
   custos de manutenção acima, sendo o decisivo a segunda fonte da verdade.
2. **Dar acesso de leitura ao warehouse do produtor.** Zero cópia e zero
   infraestrutura nova. Rejeitado por acoplar as duas cargas de trabalho: as
   consultas do marketing passam a competir por RPU com as do time de dados, e a
   conta chega toda de um lado só. Não há como saber quem gastou o quê.
3. **Datashare entre dois namespaces.** Zero cópia, faturas separadas, revogação
   imediata. Custa um segundo warehouse ligado.
4. **Replicar as tabelas para um warehouse do marketing.** Dá autonomia real ao
   consumidor. Rejeitado por ser a opção 1 com mais passos: continua sendo uma
   segunda cópia, agora com um pipeline para operar.

## Decisão

Opção 3: datashare entre um namespace produtor e um consumidor, ambos na mesma
conta, criados por este workload.

Decidiu **uma fonte da verdade**, que elimina 1 e 4. Entre 2 e 3, decidiu a
separação de faturas: a opção 2 também não copia, mas mistura as cargas e torna
impossível responder "quanto o marketing gastou consultando". Com o datashare,
cada lado paga o próprio processamento — e esse incentivo é parte do desenho,
não um detalhe de billing.

A escolha de **mesma conta** é deliberada e é o que torna o experimento viável
aqui: o handshake de duas vias entre produtor e consumidor só existe em
cross-account. Same-account é mais simples e ensina o mesmo mecanismo.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Dois warehouses ligados | Capacidade no mínimo (4 RPU cada) e teardown ao fim da sessão. Trata o sintoma; o custo segue **não medido**, e este continua sendo o item mais caro do repositório. |
| Consumidor sem autonomia | **Não é contornado.** É a contrapartida direta de não copiar. Quando autonomia for requisito — arquivamento, entrega contratual, auditoria externa — o export volta, com motivo. |
| Só funciona entre Redshifts da mesma região | Não é contornado. É o limite do mecanismo, e é o gatilho de inversão mais provável na prática. |
| `DROP TABLE` no produtor apaga para os dois | Não é contornado. Sem cópia não há rede de segurança — é o outro lado de "uma fonte da verdade". |
| Concessão por objeto inteiro, sem mascaramento | Não é contornado aqui. Filtro por linha e máscara por coluna exigem Lake Formation ou uma view intermediária no produtor — trabalho que este caminho existe justamente para evitar. |
| PII no escopo compartilhado | **Não avaliada.** `ADD ALL TABLES IN SCHEMA public` não olha conteúdo. É a dívida mais séria deste workload, e está registrada no `nfr.md`. |
| Terraform não reconcilia o SQL do share | `aws_redshiftdata_statement` roda na criação. Alterar o escopo do share depois é `ALTER DATASHARE` manual. Limite conhecido, assumido. |

## Quando esta decisão se inverte

- **Quando o consumidor não for Redshift.** Motor diferente, região diferente,
  ou uma planilha: o mecanismo não alcança, e exportar é a resposta honesta.
- **Quando autonomia virar requisito.** Se o consumidor precisa continuar
  funcionando com o produtor fora do ar, ou precisa guardar o dado por
  obrigação contratual, ele precisa de cópia — e aí a cópia é a decisão certa.
- **Quando a resposta precisar ser "sim, mas sem a coluna X".** Granularidade de
  objeto inteiro não atende, e entra governança de verdade.
- **Quando o custo dos dois workgroups for medido e não couber no orçamento.**
  Este é o primeiro candidato a sair, por ser o mais caro.

## Consequências

O repositório passou a ter um caminho em que **a fronteira entre times é uma
permissão, não um transporte** — e é o único assim. Nos demais, atravessar uma
fronteira sempre envolveu mover bytes.

Passou a existir o terceiro workload cujo custo não cai a zero sem uso — e o
único que o duplica. Isso torna a disciplina de teardown obrigatória, não
recomendável, e é a razão de o `scripts/teardown.sh` tratar os workloads de
Redshift em bloco.

A comparação com o `../federated-query/` fica direta e vale registrar: os dois
entregam defasagem zero sem copiar, mas o federado paga com carga na fonte
transacional, e este paga com um warehouse ligado. Mesmo requisito, contas
diferentes.

## Evidência no repo

- `workloads/data-sharing/main.tf:236-252` — o share inteiro: criar, adicionar
  escopo, conceder. Nenhum bucket de export, nenhum agendamento.
- `workloads/data-sharing/main.tf:260-275` — o `CREATE DATABASE FROM DATASHARE`
  no consumidor: um banco sem armazenamento próprio.
- `workloads/data-sharing/main.tf:108-147` — os dois namespaces, produtor e
  consumidor, do mesmo módulo compartilhado.
- `workloads/data-sharing/outputs.tf` — `proof_query`, o roteiro que demonstra
  ausência de defasagem sem nenhum job entre as duas leituras.
- `modules/redshift-serverless/outputs.tf` — o `namespace_id`, que é o endereço
  citado nos dois lados do share.
