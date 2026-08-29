# 0002 — Onde emular a nuvem deixa de ensinar sobre o dado

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

O repositório mantém um ambiente `local` que aponta o Terraform para o
LocalStack, e todo root module até aqui tinha `envs/local.tfvars` e
`backends/local.hcl`. A regra implícita era "todo módulo roda nos três
ambientes".

Este workload quebra a regra, e a pergunta é: **o ambiente emulado ainda ensina
alguma coisa sobre o comportamento do dado, ou só sobre a sintaxe do
Terraform?**

A distinção importa porque os dois têm valores muito diferentes. Validar que o
HCL está bem escrito é trabalho de `terraform validate`, e não precisa de
emulador nenhum. O que o `local` entrega de fato é a chance de **ver o dado se
comportar** sem gastar: o arquivo aparecendo no bucket, o job lendo, a tabela
mudando.

**Premissa:** que a fidelidade da emulação varia por serviço, e que existe um
ponto em que ela cai abaixo do útil. Se o LocalStack passar a emular os serviços
desta lista com fidelidade de comportamento, a decisão muda.

## Requisitos que decidem

| Requisito | Valor exigido | Origem |
|---|---|---|
| O que o `local` precisa ensinar | comportamento do dado, não sintaxe | este ADR, "Contexto" |
| Comportamento a observar aqui | latência real e carga na fonte | [`nfr.md`](../nfr.md) — "Impacto na fonte" |
| Serviços envolvidos | Athena, Lambda federada, Serverless App Repository | `../main.tf:152-215` |
| Fidelidade da emulação desses serviços | **insuficiente** — SAR não resolve; Athena não executa conector federado | verificado ao desenhar o workload |
| Custo de manter um `local` que não ensina | manutenção de 2 arquivos + falsa confiança | — |

O requisito que decide é o **descasamento entre o que o `local` entregaria
(sintaxe válida) e o que este workload existe para ensinar (carga na fonte e
latência real)**. Nenhum dos dois números do `nfr.md` que importam aqui pode
sair de um emulador.

## Opções consideradas

1. **Manter `local.tfvars` mesmo sem fidelidade.** Uniformidade com os outros
   módulos. Custo: quem rodar vai concluir que "funciona no local" e descobrir
   na AWS que nada do que interessa foi exercitado.
2. **Não ter ambiente `local` neste workload**, e documentar o motivo.
3. **Substituir por um `local` com Postgres em Docker e DuckDB no lugar do
   Athena**, simulando federação de mentira. Rejeitado: ensina uma arquitetura
   que não é a que o workload implementa, e o esforço de manter a farsa é maior
   que o de aplicar na AWS de verdade.

## Decisão

Opção 2: os workloads que dependem de Athena federado ou de Redshift nascem
**sem ambiente `local`**, com o motivo escrito no README.

O requisito que pesou foi o descasamento entre o que o emulador entrega e o que
o workload precisa demonstrar. Uniformidade (opção 1) perdeu para honestidade
sobre o que está sendo verificado.

Os workloads que já têm `local` **continuam com ele** — para Glue, S3 e
Iceberg a emulação ainda exercita o caminho do dado, que é o critério.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Perde-se a checagem barata antes de gastar | `terraform validate` e `terraform plan` continuam rodando sem custo e pegam a maior parte dos erros de configuração. |
| Quebra a uniformidade "todo módulo tem 3 ambientes" | Documentado no README de cada workload afetado e neste ADR, para não parecer esquecimento. |
| A CI não consegue testar aplicação de ponta a ponta | Não é contornado. A CI faz `fmt`, `validate` e `plan`; o `apply` continua atrás de aprovação humana, como nos demais. |
| Aumenta o custo de estudar este workload | Aceito — foi decisão explícita de priorizar fidelidade sobre custo neste repositório. |

## Quando esta decisão se inverte

- **Quando o LocalStack passar a executar o conector federado do Athena** e a
  resolver aplicações do Serverless Application Repository, de forma que uma
  query federada devolva linhas de verdade.
- **Quando o critério mudar de "ver o dado se comportar" para "validar
  configuração"** — aí o emulador volta a servir, e a decisão perde a base.
- Para os workloads de Redshift, o gatilho equivalente é o emulador executar SQL
  de Redshift de verdade, incluindo `MATERIALIZED VIEW` com auto refresh e
  `DATASHARE`.

## Consequências

Deixou de ser verdade que todo root module deste repositório roda nos três
ambientes. A ausência de `local` passa a ser **informação**: sinaliza que o
serviço envolvido não tem emulação que ensine comportamento.

Estudar os workloads sem `local` passou a custar dinheiro de verdade — não há
caminho gratuito para eles.

Em troca, ninguém vai mais concluir que um workload "está validado" porque
subiu no emulador quando o emulador não exercitou nada do que importa.

## Evidência no repo

- `workloads/federated-query/backends/` — só `develop.hcl` e `main.hcl`.
- `workloads/federated-query/envs/` — só `develop.tfvars` e `main.tfvars`.
- `workloads/federated-query/versions.tf:16-18` — o comentário no provider
  explicando a ausência do bloco de LocalStack.
- `workloads/amazonsales/versions.tf` — o contraste: o bloco de endpoints do
  LocalStack que os workloads de Glue/S3 mantêm.
