# workloads/federated-query

**Consultar a fonte sem copiar nada.** O Athena enxerga o Postgres transacional
como se fosse mais um schema e faz `JOIN` dele com as tabelas Iceberg do lake,
na mesma query. Nenhum job, nenhum agendamento, nenhuma cópia.

## A demanda

> *"Consegue ver se esse pedido aqui é fraude? É de agora."*

É terça, 14h. A analista de risco tem um `order_id` na mão, feito há quatro
minutos, e precisa cruzar com o histórico de comportamento daquele cliente — que
está no lake, em Iceberg, bonito e organizado.

O pedido não está lá. A carga roda de hora em hora. Ela vai ter a resposta às
15h05, e a decisão sobre segurar ou liberar o pedido é agora.

Isso acontece umas três vezes por semana.

## A resposta óbvia, e por que ela não serve

Escrever um pipeline de ingestão quase-real-time para a tabela `orders`. Ou
apertar a janela da carga de 1 hora para 5 minutos.

Não serve por três motivos, em ordem de gravidade:

1. **É desproporcional.** Uma pergunta que aparece três vezes por semana não
   justifica um fluxo que roda 288 vezes por dia, com alerta, retry e alguém de
   plantão.
2. **Você vira dono do frescor.** No minuto em que existe um pipeline
   "quase-real-time", o SLA é seu. Atrasou, é seu problema — inclusive às 3h da
   manhã, quando ninguém está fazendo análise de fraude nenhuma.
3. **Não resolve o caso.** Mesmo com 5 minutos de janela, o pedido de 4 minutos
   atrás pode não estar lá. O problema não é a frequência: é que a pergunta é
   sobre o **estado de agora**, e cópia sempre tem defasagem.

Não existe frequência de pipeline que responda "como está esse pedido neste
instante". Só a fonte responde isso.

## O que você vai ver funcionando

Um conector (Lambda, dentro da VPC) que o Athena chama quando a query referencia
o catálogo federado. O `FROM` aponta para o Postgres; o Athena empurra o filtro
para o banco, recebe as linhas e junta com o Iceberg em memória:

```sql
SELECT
    o.order_id,
    o.status,
    o.updated_at,
    h.pedidos_ultimos_90d,
    h.chargebacks
FROM "dataeng_sandbox_federated_dev_postgres"."public"."orders" AS o
LEFT JOIN lakehouse.analytics.cliente_historico AS h
       ON h.customer_id = o.customer_id
WHERE o.order_id = 90210;
```

À esquerda do `JOIN`, o estado de agora. À direita, o histórico. Uma query, duas
tecnologias, zero pipeline.

**O que medir** (vai para o `nfr.md`, e é o que dá número ao ADR):

- latência p50 e p95 da query federada × a mesma pergunta respondida pelo lake
- quantas conexões o conector abre no Postgres, e por quanto tempo
- se houve spill, e quanto
- custo por execução, isolado no workgroup próprio deste workload

## O que isso te custou

**A query bate no banco de produção.** Às 14h de uma terça, junto com os
clientes comprando. Um `WHERE` mal escrito vira um seq scan numa tabela quente,
e o time de plataforma vem perguntar o que aconteceu com a latência do checkout.
Este é o custo real e é ele que decide quando federar deixa de servir.

**Sem histórico.** Você lê o que está lá agora. Se o Postgres faz `UPDATE`
in-place — e faz — o valor anterior não existe mais para ninguém, nem para você.

**Latência imprevisível.** A query depende da saúde do OLTP no momento. Não há
p95 estável para prometer a um dashboard.

**Não escala em volume.** A Lambda tem limite de payload e de tempo; passou
disso, spill. Federação é para pergunta pontual e seletiva, não para varredura.

Nada disso é motivo para não usar — é motivo para saber **quando** usar. Está
quantificado em [`nfr.md`](aws/nfr.md) e decidido em
[`adr/0001`](aws/adr/0001-responder-sobre-o-estado-de-agora.md).

## Pré-requisitos

Este workload precisa de rede e do banco de pé. Aplique nesta ordem:

```bash
# 1. rede e Postgres (se ainda não estiverem aplicados)
cd platform/aws/network && terraform init -backend-config=backends/develop.hcl && terraform apply -var-file=envs/develop.tfvars
cd ../rds     && terraform init -backend-config=backends/develop.hcl && terraform apply -var-file=envs/develop.tfvars

# 2. este workload
cd ../workloads/federated-query
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars   # pede TF_VAR_rds_password
```

A senha vai para o Secrets Manager, não para o state nem para argumento de
Lambda:

```bash
export TF_VAR_rds_password='...'
```

Depois, no console do Athena, escolha o workgroup `dataeng-sandbox-federated-dev`
e o catálogo `dataeng_sandbox_federated_dev_postgres`. `terraform output
example_query` traz uma query pronta.

## Destruir

```bash
terraform destroy -var-file=envs/develop.tfvars
```

Os buckets de spill e de resultado têm `force_destroy = true` — são dados
intermediários deste workload e somem com ele, de propósito. O spill também
expira sozinho em 3 dias, caso você esqueça.

## Sem ambiente `local`

Não há `envs/local.tfvars` aqui. O conector vem do Serverless Application
Repository, que não existe fora da AWS — aplicar contra um emulador validaria
sintaxe de Terraform e não o comportamento que este workload existe para
ensinar. O motivo está em
`adr/0001` na raiz.

## Requisitos e decisões

- [`nfr.md`](aws/nfr.md) — os números
- [`adr/0001`](aws/adr/0001-responder-sobre-o-estado-de-agora.md) — como responder uma pergunta sobre o estado de agora
