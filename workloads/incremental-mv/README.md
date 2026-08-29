# workloads/incremental-mv

**Um agregado sempre pronto, sem ninguém agendar a recomputação.** Você declara
o resultado que deve valer; o motor decide quando recalcular, e recalcula só o
que mudou. Não há job, não há cron, não há backfill.

## A demanda

> *"O dashboard de receita por hora demora 40 segundos para abrir."*

E ele é aberto umas 200 vezes por dia. Toda vez, o mesmo `GROUP BY` sobre as
mesmas linhas, produzindo o mesmo resultado — porque 99% dos dados agregados são
de ontem e não mudam mais.

O time comercial já parou de abrir. Eles pedem print no chat.

## A resposta óbvia, e por que ela não serve

Materializar o agregado com um job agendado: um Glue de 5 em 5 minutos, ou uma
Step Function de hora em hora, escrevendo numa tabela `receita_por_hora`.

Funciona. E te entrega quatro coisas que você não pediu:

1. **Você vira dono do "quando".** Qual a frequência certa? 5 minutos gasta à
   toa de madrugada; 1 hora deixa o dashboard velho às 9h. Você vai errar nos
   dois sentidos e ajustar para sempre.
2. **Você vira dono do incremental.** Recomputar tudo é caro; recomputar só o
   que mudou exige saber o que mudou — janela, watermark, reprocessamento de
   linha atrasada. É a parte onde os bugs moram.
3. **Você vira dono da falha.** O job falhou às 3h. O dashboard das 9h está
   velho. Alguém precisa ser acordado, ou alguém vai reclamar.
4. **Você vira dono do backfill.** Mudou a regra do agregado? Recalcule três
   meses, à mão, com cuidado para não duplicar.

Nada disso é sobre receita por hora. É tudo sobre operar um agendamento — e o
pedido não tinha agendamento nenhum. O pedido era *"que esteja pronto"*.

## O que você vai ver funcionando

Uma materialized view declarada uma vez, com duas palavras que mudam quem é
dono do problema:

```sql
CREATE MATERIALIZED VIEW receita_por_hora
  AUTO REFRESH YES
AS
SELECT DATE_TRUNC('hour', pedido_em) AS hora,
       COUNT(*)                      AS pedidos,
       SUM(valor)                    AS receita
FROM vendas
GROUP BY 1;
```

O dashboard consulta `receita_por_hora` e recebe o resultado pronto. Ninguém
agendou nada.

**Como ver o motor trabalhando sem você:**

```sql
-- 1. insira linhas novas na tabela base
INSERT INTO vendas VALUES (99, 42, GETDATE(), 199.90, 'pago');

-- 2. NÃO faça refresh. Espere. Depois consulte a view:
SELECT * FROM receita_por_hora ORDER BY hora DESC LIMIT 5;

-- 3. e veja quem fez o trabalho:
SELECT mv_name, status, refresh_type, starttime
  FROM SVL_MV_REFRESH_STATUS
 WHERE mv_name = 'receita_por_hora'
 ORDER BY starttime DESC;
```

A linha com `refresh_type = 'Auto'` é a prova: o agregado está fresco e você não
pediu. `terraform output check_refresh_query` traz essa consulta pronta.

**O que medir** (vai para o [`nfr.md`](nfr.md)):

- latência da mesma query com e sem a view (é o "40 segundos" da demanda)
- intervalo real entre refreshes automáticos, e quanto ele varia
- RPU consumida pelos refreshes que ninguém pediu
- o que acontece com a defasagem quando a carga de escrita sobe

## O que isso te custou

**Você deixou de controlar o "quando" — nos dois sentidos.** Ganhou não precisar
agendar; perdeu poder garantir. O motor decide com base em carga e em quanto a
base mudou. Não existe SLA de frescor para prometer a ninguém, e há momentos em
que a view está mais velha do que um cron de 5 minutos deixaria.

**Custo que aparece sem consulta nenhuma.** Cada refresh automático consome RPU.
Numa madrugada sem ninguém olhando dashboard, a base recebe escrita, o motor
recalcula, e a fatura anda. É o oposto do modelo de Glue e Lambda, que só cobram
quando alguém pede.

**A view aceita menos SQL do que você imagina.** Auto refresh não vale para
qualquer consulta: há restrições de funções, de junções e de views sobre views.
Uma regra de negócio um pouco mais elaborada não cabe — e aí o job agendado
volta a ser a resposta, agora com motivo.

**O Terraform declara, mas não reconcilia.** O SQL roda uma vez, na criação
(`aws_redshiftdata_statement`). Mudar a definição da view no `main.tf` recria o
statement, não altera o objeto no banco. Alterar a view de verdade é `DROP` e
`CREATE` à mão. Essa fronteira é real e está no ADR.

Está quantificado em [`nfr.md`](nfr.md) e decidido em
[`adr/0001`](adr/0001-servir-um-agregado-sempre-pronto.md).

## Pré-requisitos

```bash
# 1. rede (se ainda não estiver aplicada)
cd platform/network && terraform init -backend-config=backends/develop.hcl && terraform apply -var-file=envs/develop.tfvars

# 2. este workload
cd ../../workloads/incremental-mv
export TF_VAR_redshift_admin_password='...'   # 8-64 chars, maiúscula, minúscula e número
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars
```

Não precisa de fonte externa: o dado deste workload vive no próprio Redshift.

**Com dados de verdade.** Por padrão a tabela base sobe vazia e você insere
linhas à mão — o suficiente para ver o auto refresh acontecer. Para medir número
comparável com os outros workloads, aponte a semente para o parquet do lake em
`envs/develop.tfvars`:

```hcl
seed_bucket = "seu-prefixo-lake-raw"
seed_prefix = "datasets/vendas/"
```

O contrato que torna esses números comparáveis está em
[`../DATASET.md`](../DATASET.md) — leia a seção final antes de confiar em
qualquer medição.

## Destruir

```bash
terraform destroy -var-file=envs/develop.tfvars
```

O Redshift Serverless cobra por RPU enquanto processa, e o auto refresh o faz
processar sozinho. **Destruir ao fim da sessão não é higiene, é orçamento.**

## Sem ambiente `local`

Não há `envs/local.tfvars`. Materialized view com auto refresh é comportamento
de motor, e não há Redshift em contêiner — não há o que validar contra
um emulador aqui. Ver
[`adr/0001` na raiz](../../adr/0001-rodar-local-sem-emular-a-nuvem.md).

## Requisitos e decisões

- [`nfr.md`](nfr.md) — os números
- [`adr/0001`](adr/0001-servir-um-agregado-sempre-pronto.md) — como servir um agregado sempre pronto sem virar dono do agendamento
