# NFR — `zero-etl`

Requisitos não-funcionais do caminho que replica o OLTP inteiro sem código
próprio. **Documento vivo:** quando um número muda aqui, os ADRs que dependem
dele viram candidatos a revisão.

**Última revisão:** 2026-08-29
**Dataset de referência:** [`../DATASET.md`](../../DATASET.md) `v1` — os números de
latência e custo abaixo só são comparáveis com os dos outros workloads se
tiverem sido medidos sobre a mesma versão do dataset.

## A pergunta que este caminho responde

| Requisito | Valor hoje | Origem |
|---|---|---|
| Frescor exigido pela pergunta | minutos | `README.md:7-17` |
| Defasagem tolerada | **minutos** — não zero, não horas | `README.md:7-17` |
| Transformação exigida | **nenhuma** — é o que viabiliza a escolha | `README.md:19-39` |
| Histórico exigido | nenhum no destino | `README.md:74-100` |
| Escopo | o banco inteiro, não uma tabela | `infra/variables.tf:53-62` (`source_tables`) |
| Esforço de manutenção aceito | **zero linha de código operada** | `README.md:19-39` |

A linha que decide é **transformação exigida = nenhuma**. No instante em que
alguém pedir uma regra de negócio no meio do caminho, este workload deixa de
servir e a resposta volta a ser um pipeline.

## Execução

| Requisito | Valor hoje | Origem |
|---|---|---|
| Motor | integração gerenciada RDS → Redshift | `infra/main.tf:123-133` |
| Código próprio a operar | **0 linhas** | — |
| Versão mínima da origem | PostgreSQL 15.4 | restrição do serviço |
| Versão da origem hoje | PostgreSQL 17 | `../../platform/aws/modules/rds/` |
| Destino | Redshift Serverless, 4 RPU base | `infra/variables.tf:43-51` |
| `case_sensitive_identifier` | `true` — exigido pela integração | `infra/main.tf:86` |
| Filtro de tabelas | `dataengsandbox.public.*` | `infra/envs/develop.tfvars:10` |
| Defasagem medida origem → destino | **não medida** | — |
| Tempo da carga inicial | **não medido** | — |
| Comportamento sob `ALTER TABLE` na origem | **não observado** | — |

**A linha de defasagem medida é a mais importante da tabela.** Sem ela, "zero-ETL
é quase em tempo real" é marketing repetido, não requisito verificado — e é
exatamente o número que separa este caminho do `../federated-query/` (defasagem
zero) e do `../dms/` (defasagem que você controla).

## Impacto na fonte

| Requisito | Valor hoje | Origem |
|---|---|---|
| Mecanismo de leitura | replicação lógica do Postgres | comportamento do serviço |
| Slot de replicação na origem | criado e mantido pela AWS | comportamento do serviço |
| Risco de acúmulo de WAL se o destino parar | **existe, não medido** | — |
| Aumento de carga na origem | **não medido** | — |

O risco de WAL é o que morde de verdade: se o destino ficar indisponível e o
slot não avançar, o Postgres retém WAL e o disco da instância enche. Numa
`db.t4g.micro` isso chega rápido.

## Custo

| Requisito | Valor hoje | Origem |
|---|---|---|
| Custo da integração em si | **US$0** — o serviço não cobra pela integração | modelo do serviço |
| Custo do destino parado | **≠ US$0** — o Redshift cobra por RPU ao processar, e a integração o faz processar sem consulta | `README.md:74-100` |
| Capacidade mínima | 4 RPU (mínimo do serviço em us-east-2) | `infra/variables.tf:43-51` |
| Armazenamento no destino | cópia integral do escopo replicado | `infra/envs/develop.tfvars:10` |
| Custo por hora medido | **não medido** | — |
| Custo comparado ao `../dms/` fazendo o mesmo | **não medido** | — |

**Este é o workload mais caro do repositório** e o único cujo custo não cai a
zero quando ninguém usa. É o motivo de o `README.md` da raiz pedir `terraform
destroy` ao fim da sessão, e de o `scripts/teardown.sh` colocá-lo antes do RDS.

## Consequências desta tabela

**"Zero código" não é "zero custo".** O que se economiza em engenharia se paga
em infraestrutura ligada. A comparação honesta com o `../dms/` não é
"gerenciado × próprio", é "US$X/hora parado × N horas de manutenção por mês" — e
nenhum dos dois lados está medido hoje.

**Transformação nenhuma é premissa, não resultado.** O destino recebe o schema
do OLTP como ele é. O primeiro pedido de "renomeia essa coluna" derruba a
escolha inteira.

**Sem histórico no destino, este caminho não substitui o `../dms/`.** Eles
resolvem o mesmo transporte e coisas diferentes: um entrega o estado atual sem
trabalho, o outro entrega o passado ao custo de trabalho. Colocá-los lado a lado
é o experimento que este repositório existe para fazer.
