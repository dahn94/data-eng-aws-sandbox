# NFR — `data-sharing`

Requisitos não-funcionais do caminho que entrega dado a outro time sem criar uma
segunda cópia. **Documento vivo:** quando um número muda aqui, os ADRs que
dependem dele viram candidatos a revisão.

**Última revisão:** 2026-08-29
**Dataset de referência:** [`../DATASET.md`](../DATASET.md) `v1` — os números de
latência e custo abaixo só são comparáveis com os dos outros workloads se
tiverem sido medidos sobre a mesma versão do dataset.

## A pergunta que este caminho responde

| Requisito | Valor hoje | Origem |
|---|---|---|
| O que o consumidor precisa | **acesso**, não transporte | `README.md:34-37` |
| Frescor exigido | o dado como está agora | `README.md:39-66` |
| Defasagem tolerada | **zero** — e sai de graça, porque não há transporte | `README.md:65-66` |
| Número de fontes da verdade aceitas | **uma** | `README.md:17-37` |
| Autonomia exigida do consumidor | **nenhuma** — ele pode depender do produtor | `README.md:78-96` |
| Motor do consumidor | Redshift, mesma região | `README.md:78-96` |

A linha que decide é **número de fontes da verdade = uma**. É ela que elimina o
export: qualquer cópia entregue cria a segunda fonte, e a divergência é questão
de semanas.

A linha que **limita** é o motor do consumidor. Marketing em BigQuery ou em
Excel não é atendido por este caminho, por melhor que ele seja.

## Execução

| Requisito | Valor hoje | Origem |
|---|---|---|
| Mecanismo | datashare entre namespaces da mesma conta | `main.tf:236-252` |
| Cópia de dado | **nenhuma** | `main.tf:260-275` |
| Job a operar | **nenhum** | — |
| Código próprio a operar | **0 linhas** | — |
| Escopo do share | todas as tabelas do schema `public` do produtor | `main.tf:243-244` |
| Handshake entre as pontas | dispensado — só existe em cross-account | `main.tf:260-275` |
| Defasagem medida produtor → consumidor | **não medida** (esperada: zero) | — |
| Latência da mesma query nas duas pontas | **não medida** | — |
| Reconciliação do SQL pelo Terraform | **não existe** — roda uma vez, na criação | `main.tf:236-252` |

**"Defasagem esperada: zero" precisa virar "defasagem medida: zero".** É a
afirmação central do workload, e hoje ela é teoria — o consumidor lê o
armazenamento do produtor, então não deveria haver atraso algum, mas ninguém
verificou.

## Governança

Esta tabela não existe nos outros workloads. Compartilhar dado é um ato de
governança, e o que este caminho **não** resolve importa tanto quanto o que ele
resolve:

| Requisito | Valor hoje | Origem |
|---|---|---|
| Granularidade da concessão | objeto inteiro (schema, tabela) | `main.tf:243-244` |
| Mascaramento por coluna | **não existe aqui** | `README.md:94-96` |
| Filtro por linha | **não existe aqui** | `README.md:94-96` |
| Auditoria de quem leu o quê | **não configurada** | — |
| Revogação de acesso | imediata — `REVOKE` corta a leitura na hora | comportamento do serviço |
| PII no escopo compartilhado | **não avaliada** | — |

A linha de revogação é a vantagem estrutural sobre o export: um CSV entregue não
volta. Um datashare se revoga com um comando, e o acesso acaba no mesmo instante.

A linha de PII é a dívida: `ADD ALL TABLES IN SCHEMA public` não olha o conteúdo.

## Custo

| Requisito | Valor hoje | Origem |
|---|---|---|
| Workgroups criados | **2** — é o único workload do repositório com dois | `main.tf:108-147` |
| Capacidade base por workgroup | 4 RPU | `variables.tf:33-41` |
| Custo parado | **≠ US$0, dobrado** | `README.md:78-96` |
| Armazenamento duplicado | **nenhum** — o consumidor não guarda nada | `main.tf:260-275` |
| Quem paga a consulta do consumidor | o consumidor, no próprio workgroup | modelo do serviço |
| Custo por hora medido | **não medido** | — |

**Este é o item mais caro do repositório**, e a separação de faturas é parte do
que ele ensina: no modelo de export, o produtor paga para gerar o arquivo e o
consumidor não paga nada; aqui cada lado paga o próprio processamento. Isso muda
o incentivo de quem consulta.

## Consequências desta tabela

**Zero cópia compra defasagem zero e cobra autonomia zero.** O consumidor não
sobrevive ao produtor. Um export, com todos os seus defeitos, sobrevive — e há
casos em que essa é justamente a propriedade desejada (arquivamento, entrega
contratual, auditoria externa).

**Revogação imediata é a diferença que não aparece na conversa.** O pedido era
"manda o CSV"; a contraproposta entrega acesso ao vivo *e* a capacidade de tirar
o acesso. Nenhum pipeline de export oferece a segunda parte.

**A granularidade de objeto inteiro é o teto do caminho.** No dia em que a
resposta precisar ser "sim, mas sem a coluna `cpf`", este mecanismo sozinho não
serve — entra Lake Formation, ou uma view intermediária no produtor, que é
trabalho de novo.
