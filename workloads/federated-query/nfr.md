# NFR — `federated-query`

Requisitos não-funcionais do caminho que consulta a fonte transacional sem
copiar dado. **Documento vivo:** quando um número muda aqui, os ADRs que
dependem dele viram candidatos a revisão.

**Última revisão:** 2026-08-28
**Dataset de referência:** [`../DATASET.md`](../DATASET.md) — os números de
latência e custo abaixo só são comparáveis com os dos outros workloads se
tiverem sido medidos sobre a mesma versão do dataset.

## A pergunta que este caminho responde

| Requisito | Valor hoje | Origem |
|---|---|---|
| Frescor exigido pela pergunta | **estado do instante da consulta** | `README.md:19-27` |
| Defasagem tolerada | **zero** — é o que define o caso | `README.md:44-48` |
| Frequência da pergunta | ~3× por semana, sob demanda | `README.md:29` |
| Histórico exigido | nenhum — a pergunta é sobre agora | `README.md:97` |
| Seletividade | alta: filtro por chave primária | `README.md:72-80` |
| Volume por consulta | dezenas a centenas de linhas | `README.md:110-112` |

A linha que decide tudo é **defasagem tolerada = zero**. Nenhuma frequência de
carga responde "como está este pedido neste instante" — só a fonte responde.

## Execução

| Requisito | Valor hoje | Origem |
|---|---|---|
| Motor | Athena + conector Lambda | `main.tf:152-178` |
| Memória da Lambda do conector | 1024 MB | `variables.tf:58-65` (`connector_lambda_memory_mb`) |
| Timeout da Lambda do conector | 300 s | `variables.tf:67-71` (`connector_lambda_timeout_s`) |
| Teto do Athena por chamada ao conector | 900 s | limite do serviço |
| Isolamento de custo | workgroup próprio | `main.tf:196-215` |
| Retenção do spill | 3 dias | `variables.tf:73-77` (`spill_retention_days`) |
| Latência p50 da query federada | **não medida** | — |
| Latência p95 da query federada | **não medida** | — |
| Conexões simultâneas abertas no Postgres | **não medido** | — |
| Frequência de spill | **não medida** | — |

## Impacto na fonte

Esta é a tabela que não existe nos outros workloads, e é a que importa aqui:
federar transfere carga para o banco transacional.

| Requisito | Valor hoje | Origem |
|---|---|---|
| Janela em que a consulta acontece | horário comercial, junto do tráfego real | `README.md:21` |
| Aumento de CPU no RDS durante a query | **não medido** | — |
| Impacto na latência do OLTP | **não medido** | — |
| Teto de carga aceitável na fonte | **não declarado** | — |
| Limite de conexões do `db.t4g.micro` | herdado do `max_connections` padrão | `../../modules/rds/` |

**Os três "não medido" desta tabela são os números mais importantes do
workload.** Sem eles, "federação sobrecarrega o banco" é folclore, não
engenharia — e é exatamente a afirmação que o
[`adr/0001`](adr/0001-responder-sobre-o-estado-de-agora.md) precisa sustentar
para dizer quando esta decisão se inverte.

## Custo

| Requisito | Valor hoje | Origem |
|---|---|---|
| Custo parado | **US$0** — Lambda e Athena cobram por uso | `README.md:33` (tabela do repo) |
| Custo por consulta | invocação da Lambda + bytes escaneados pelo Athena | modelo dos serviços |
| Custo de ingestão | **US$0** — não há pipeline para operar | — |
| Custo de armazenamento | só o spill, expirado em 3 dias | `main.tf:63-77` |
| Custo por execução medido | **não medido** | — |

## Consequências desta tabela

**Defasagem zero é a única linha que justifica este caminho.** Some ela, e
qualquer pipeline batch é melhor: mais barato por consulta, previsível, e sem
tocar na fonte.

**Custo de ingestão zero é o que torna a federação atraente cedo demais.** É
fácil federar tudo porque nada precisa ser construído. A conta chega na tabela
de impacto na fonte, que hoje está vazia.

**Alta seletividade é premissa, não resultado.** Este caminho serve para
filtro por chave. Uma varredura de tabela cheia bate no limite de payload da
Lambda, cai em spill, e vira o pior dos dois mundos: lento e ainda por cima
pesado para o OLTP.
