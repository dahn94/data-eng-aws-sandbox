# NFR — `incremental-mv`

Requisitos não-funcionais do caminho que mantém um agregado pronto sem
agendamento próprio. **Documento vivo:** quando um número muda aqui, os ADRs que
dependem dele viram candidatos a revisão.

**Última revisão:** 2026-08-29
**Dataset de referência:** [`../DATASET.md`](../DATASET.md) `v1` — os números de
latência e custo abaixo só são comparáveis com os dos outros workloads se
tiverem sido medidos sobre a mesma versão do dataset.

## A pergunta que este caminho responde

| Requisito | Valor hoje | Origem |
|---|---|---|
| Latência exigida na leitura | **< 2 s** (hoje são 40 s) | `README.md:7-15` |
| Frequência da leitura | ~200× por dia | `README.md:11` |
| Frescor exigido pelo consumo | minutos; o dado é histórico agregado por hora | `README.md:7-15` |
| Defasagem tolerada | **minutos, sem garantia contratual** | `README.md:83-106` |
| Fração da base que muda | pequena — quase tudo é de ontem e não muda mais | `README.md:11-15` |
| Complexidade do agregado | `GROUP BY` simples com `SUM` e `COUNT` | `main.tf:218-226` |

A linha que decide é **frequência da leitura × latência exigida**: 200 leituras
por dia do mesmo resultado é a definição de trabalho repetido, e é o que paga a
materialização. A que viabiliza a escolha é **defasagem sem garantia** — quem
exige SLA de frescor não pode usar auto refresh.

## Execução

| Requisito | Valor hoje | Origem |
|---|---|---|
| Motor | Redshift Serverless, materialized view | `main.tf:109-130` |
| Quem decide recomputar | **o motor** | `main.tf:212-233` (`AUTO REFRESH`) |
| Código próprio a operar | **0 linhas** | — |
| Capacidade base | 8 RPU | `variables.tf:33-42` |
| Distribuição da tabela base | `DISTKEY (customer_id)`, `SORTKEY (pedido_em)` | `main.tf:175-184` |
| Latência da query sem a view | **não medida** (40 s é o relato da demanda, não medição) | `README.md:9` |
| Latência da query com a view | **não medida** | — |
| Intervalo real entre refreshes automáticos | **não medido** | — |
| Variação desse intervalo sob carga | **não medida** | — |
| Defasagem máxima observada | **não medida** | — |

**As três últimas linhas são o que separa este workload de um cron.** Um job
agendado tem intervalo conhecido e ruim; o auto refresh tem intervalo
desconhecido e provavelmente melhor. Sem medir, a escolha entre os dois é
estética.

## Restrições do mecanismo

Esta tabela não existe nos outros workloads e é a que define até onde o caminho
vai:

| Requisito | Valor hoje | Origem |
|---|---|---|
| SQL suportado em auto refresh | subconjunto: há restrição de função, junção e view sobre view | restrição do serviço |
| A definição da view cabe nesse subconjunto? | **sim, hoje** — `GROUP BY` com `SUM`/`COUNT` | `main.tf:218-226` |
| Margem para o agregado crescer em complexidade | **não avaliada** | — |
| Reconciliação da definição pelo Terraform | **não existe** — o SQL roda uma vez, na criação | `main.tf:165-168` |

A última linha é uma limitação de IaC assumida, não um bug: alterar a view exige
`DROP` e `CREATE` manuais.

## Custo

| Requisito | Valor hoje | Origem |
|---|---|---|
| Custo parado | **≠ US$0** — refresh automático consome RPU sem consulta | `README.md:83-106` |
| Capacidade mínima | 8 RPU por workgroup | `variables.tf:33-42` |
| Custo por leitura do dashboard | baixo — lê o agregado, não a base | modelo do serviço |
| Custo dos refreshes que ninguém pediu | **não medido** | — |
| Armazenamento | tabela base + o agregado materializado | `main.tf:175-184` |
| Custo comparado a um job Glue agendado | **não medido** | — |

**A última linha é a comparação que este workload existe para fazer.** Glue cobra
por execução; Redshift Serverless cobra por RPU enquanto processa. Numa base que
muda pouco, o auto refresh pode ser mais barato que um cron de 5 minutos — ou
muito mais caro, se recalcular sem necessidade. Hoje é palpite.

## Consequências desta tabela

**Trocar dono do "quando" é a decisão inteira.** Todo o resto — latência, custo,
código — decorre disso. Quem precisa prometer frescor a alguém não pode fazer
essa troca, por melhor que o número saia.

**Custo parado ≠ US$0 aproxima este workload do `../zero-etl/` e o afasta de
todo o resto do repositório.** Glue, Lambda e Athena cobram por uso; estes dois
cobram por existir. É o eixo de custo que o `README.md` da raiz precisa deixar
explícito.

**A restrição de SQL é o teto real do caminho.** Ele resolve agregado simples e
repetido. Regra de negócio elaborada não cabe, e aí o job agendado volta a ser a
resposta certa — com motivo, e não por hábito.
