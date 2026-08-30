# NFR — `incremental-mv`

Requisitos não-funcionais do caminho que mantém um agregado pronto sem
agendamento próprio. **Documento vivo:** quando um número muda aqui, os ADRs que
dependem dele viram candidatos a revisão.

**Última revisão:** 2026-08-29
**Dataset de referência:** [`../DATASET.md`](../../DATASET.md) `v1` — os números de
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
| Complexidade do agregado | `GROUP BY` simples com `SUM` e `COUNT` | `infra/main.tf:218-226` |

A linha que decide é **frequência da leitura × latência exigida**: 200 leituras
por dia do mesmo resultado é a definição de trabalho repetido, e é o que paga a
materialização. A que viabiliza a escolha é **defasagem sem garantia** — quem
exige SLA de frescor não pode usar auto refresh.

## Execução

| Requisito | Valor hoje | Origem |
|---|---|---|
| Motor | Redshift Serverless, materialized view | `infra/main.tf:109-130` |
| Quem decide recomputar | **o motor** | `infra/main.tf:212-233` (`AUTO REFRESH`) |
| Código próprio a operar | **0 linhas** | — |
| Capacidade base | 4 RPU | `infra/variables.tf:33-42` |
| Distribuição da tabela base | `DISTKEY (customer_id)`, `SORTKEY (pedido_em)` | `infra/main.tf:175-184` |
| Latência da query sem a view | **10 ms p50** sobre 2 M linhas — medido em ClickHouse, não em Redshift | `local/` |
| Latência da query com a view | **1 ms p50**, lendo 17 linhas em vez de 2 M | `local/` |
| Intervalo real entre refreshes automáticos | **não medido, e não medível local** — o ClickHouse atualiza na escrita; intervalo só existe no Redshift | — |
| Variação desse intervalo sob carga | **não medível local** — mesma razão | — |
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
| A definição da view cabe nesse subconjunto? | **sim, hoje** — `GROUP BY` com `SUM`/`COUNT` | `infra/main.tf:218-226` |
| Margem para o agregado crescer em complexidade | **não avaliada** | — |
| Reconciliação da definição pelo Terraform | **não existe** — o SQL roda uma vez, na criação | `infra/main.tf:165-168` |

A última linha é uma limitação de IaC assumida, não um bug: alterar a view exige
`DROP` e `CREATE` manuais.

## Custo

| Requisito | Valor hoje | Origem |
|---|---|---|
| Custo parado | **≠ US$0** — refresh automático consome RPU sem consulta | `README.md:83-106` |
| Capacidade mínima | 4 RPU por workgroup (mínimo do serviço em us-east-2) | `infra/variables.tf:33-42` |
| Custo por leitura do dashboard | baixo — lê o agregado, não a base | modelo do serviço |
| Custo dos refreshes que ninguém pediu | **não medido** | — |
| Armazenamento | tabela base + o agregado materializado | `infra/main.tf:175-184` |
| Custo comparado a um job Glue agendado | **não medido** | — |

**A última linha é a comparação que este workload existe para fazer.** Glue cobra
por execução; Redshift Serverless cobra por RPU enquanto processa. Numa base que
muda pouco, o auto refresh pode ser mais barato que um cron de 5 minutos — ou
muito mais caro, se recalcular sem necessidade. Hoje é palpite.

## Medições locais — em ClickHouse, não em Redshift

Feitas em 2026-08-30 em `local/`, com 2 milhões de linhas geradas
deterministicamente e agregadas em 24 grupos horários.

| Caminho | p50 | p95 | linhas lidas | bytes lidos |
|---|---|---|---|---|
| **Sem a view** — `GROUP BY` sobre a base | 10 ms | 18 ms | 2.000.000 | 22,89 MiB |
| **Com a view** — lendo o agregado | **1 ms** | 2 ms | **17** | **755 B** |

**O número que importa não é o tempo, é o volume lido.** Dez vezes mais rápido
impressiona pouco; ler 17 linhas em vez de dois milhões — cerca de 30.000 vezes
menos dado — é o que a materialização compra, e é o que continua valendo quando
o motor muda.

O ClickHouse é rápido demais para essa diferença aparecer bem no relógio: 2 M
linhas em 10 ms. **Num motor onde a leitura domina — Redshift lendo de disco, ou
Athena escaneando S3 e cobrando por byte — a mesma razão de volume vira razão de
tempo e de custo.** É por isso que a linha de bytes lidos é a que se deve
carregar para a comparação, e não a de milissegundos.

**O que estas medições não cobrem:** o intervalo entre refreshes e sua variação
sob carga. Não é falta de esforço — é que a pergunta não existe aqui. O
ClickHouse atualiza na escrita; "quando o motor decide recomputar" só faz
sentido no Redshift, e é justamente a contrapartida que o
`adr/0001` aceita. Essas linhas
só saem do "não medido" com a AWS de pé.

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
