# 0001 — Como rodar local sem emular a nuvem

**Status:** Aceito
**Data do registro:** 2026-08-29
**Substitui:** a decisão anterior, que mantinha o LocalStack para os workloads
de Glue, S3 e Iceberg e o dispensava só para Athena e Redshift. O critério era o
mesmo; a resposta mudou quando ele foi aplicado com honestidade a todos.

## Contexto e problema

O repositório mantinha um ambiente `local` que apontava o Terraform para o
LocalStack, com `envs/local.tfvars` e `backends/local.hcl` em cada root module.

A pergunta que decide é: **o ambiente emulado ensina alguma coisa sobre o
comportamento do dado, ou só sobre a sintaxe do Terraform?**

A distinção importa porque os dois valem coisas muito diferentes. Validar que o
HCL está bem escrito é trabalho de `terraform validate`, e não precisa de
emulador nenhum. O que um ambiente local precisa entregar é a chance de **ver o
dado se comportar**: o arquivo aparecendo no bucket, o job lendo, a linha
duplicada sendo descartada, o campo pessoal sumindo.

Aplicado a todos os workloads, o critério dá uma resposta desconfortável. O
próprio README do LocalStack neste repositório já admitia o essencial:

> **Criar um job Glue ≠ executar um job Glue.**

Isso significa que as afirmações centrais dos ADRs — o dedup do CDC escolhendo
uma linha por chave, o contrato de schema barrando coluna nova, o ponto onde o
dado pessoal é descartado, a semântica at-least-once do destino — **não eram
verificadas por nada**. O emulador criava os recursos e nunca executava a
lógica que este repositório existe para defender.

Some-se um fato prático: a imagem usada é a Pro, e exige `LOCALSTACK_AUTH_TOKEN`.
Sem licença, nem a emulação rasa funciona.

**Premissa:** que os scripts dos workloads são PySpark comum, e que Spark,
Kafka, Postgres, OpenSearch e um catálogo Iceberg rodam em contêiner sem
emulação nenhuma. Se isso deixar de ser verdade, a decisão muda.

## Requisitos que decidem

| Requisito | Valor exigido | Origem |
|---|---|---|
| O que o ambiente local precisa ensinar | comportamento do dado, não sintaxe | este ADR, "Contexto" |
| Cobertura da lógica dos jobs pelo emulador | **nenhuma** — cria o recurso, não executa Spark | o README do LocalStack, antes da remoção |
| Fidelidade para Athena federado e Redshift | **inexistente** | verificado ao desenhar os workloads |
| Licença exigida | LocalStack Pro (`LOCALSTACK_AUTH_TOKEN`) | `docker-compose.yml`, antes da remoção |
| Alternativa em contêiner para os motores | existe, e com `arm64` | MinIO, Trino, Iceberg REST, e imagens oficiais da AWS para Glue e Step Functions |
| Custo de manter os dois caminhos | 11 arquivos de ambiente + bloco de endpoints em 6 `versions.tf` | — |

O requisito que decide é **cobertura da lógica dos jobs = nenhuma**. Um
ambiente local que não executa a lógica não cumpre o que se pede dele, por mais
uniforme que pareça.

## Opções consideradas

1. **Manter o LocalStack como estava.** Uniformidade: todo módulo com três
   ambientes. Rejeitado porque a uniformidade era aparente — metade dos
   workloads já não tinha `local`, e nos que tinham o emulador não exercitava
   nada do que os ADRs afirmam.
2. **Manter o LocalStack e adicionar motores reais ao lado.** Cobre os dois
   casos. Rejeitado pelo custo de manter dois caminhos que se sobrepõem, sendo
   que um deles não entrega o que interessa — e ainda exige licença paga.
3. **Remover o LocalStack e trocar o ambiente local por motores reais em
   contêiner**, aceitando que `local` deixa de ser um ambiente de Terraform.
4. **Não ter ambiente local nenhum**, e estudar só contra a AWS. Rejeitado: joga
   fora a possibilidade de verificar a lógica de graça, que é exatamente o que a
   opção 3 recupera.

## Decisão

Opção 3. O LocalStack sai do repositório. `local` deixa de significar "a mesma
infraestrutura contra um emulador" e passa a significar **os motores de verdade,
em contêiner, executando os mesmos scripts**.

O que decidiu foi a cobertura da lógica. Entre um caminho que cria recursos sem
executá-los e um que executa a lógica sem criar recursos, o segundo é o que
responde às perguntas que este repositório faz.

Consequência direta e aceita: **não existe mais ambiente `local` no Terraform.**
Não há para onde apontar o provider — MinIO fala S3, mas não fala IAM, Glue,
DMS nem RDS. Sobram `develop` e `main`.

O mapa que substitui o emulador, todas as imagens com `arm64`:

| AWS | Local | Origem |
|---|---|---|
| S3 | MinIO | open source |
| S3 Tables / catálogo Iceberg | `apache/iceberg-rest-fixture` | Apache |
| Glue (Spark) | `public.ecr.aws/glue/aws-glue-libs` | **oficial AWS** |
| Step Functions | `amazon/aws-stepfunctions-local` | **oficial AWS** |
| Athena | Trino | é o motor por trás do Athena |
| DMS | Debezium | já existia em `platform/local/streaming-cdc` |
| RDS | Postgres | já existia |
| OpenSearch | OpenSearch | já existia |

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Perde-se a checagem de configuração antes de gastar | `terraform validate` e `terraform plan` continuam de graça e pegam a maior parte dos erros de HCL — que é o que o emulador de fato entregava. |
| Redshift não tem equivalente em contêiner | **Não é contornado.** O ClickHouse ensina o mecanismo de materialized view mantida pelo motor, mas `DATASHARE` e zero-ETL só existem na AWS. Os três workloads de Redshift já nasciam sem ambiente local. |
| Debezium não é DMS | Não é contornado. São implementações diferentes de CDC; a semântica que o `dms/adr/0001` discute precisa da AWS para ser medida. |
| Trino não é Athena | Athena **é** Trino gerenciado, então a fidelidade de motor é alta. O que não se reproduz é o modelo de cobrança por bytes escaneados. |
| Mais contêineres para manter | Aceito. São imagens oficiais ou projetos de primeira linha, e substituem um serviço que exigia licença paga. |

## Quando esta decisão se inverte

- **Quando existir um emulador que execute a lógica**, e não só crie recursos —
  um que rode um job Glue de verdade sobre dado de verdade. Aí o argumento
  central cai.
- **Quando o critério mudar de "ver o dado se comportar" para "validar
  configuração"** — nesse caso nem emulador nem motores são necessários:
  `validate`, `tflint` e políticas resolvem melhor e mais barato.
- **Se os scripts deixarem de ser PySpark comum** e passarem a depender de
  extensões exclusivas do Glue que não rodam na imagem oficial da AWS.

## Consequências

Deixou de existir um caminho para "aplicar a infraestrutura sem gastar". Quem
quiser ver os recursos existirem paga a AWS; quem quiser ver o dado se comportar
sobe os contêineres. As duas coisas foram separadas de propósito, porque eram
duas coisas o tempo todo.

O Terraform ficou menor: sumiram 11 arquivos de ambiente, o bloco `endpoints`
de 6 `versions.tf`, a variável `aws_endpoint_url` e as flags
`skip_credentials_validation` e afins. O provider passou a ter uma configuração
só, sem condicional.

Este ADR mudou de lugar. Nasceu em `workloads/federated-query/adr/0002` porque
era sobre um workload; virou decisão do repositório inteiro e passou para
`adr/`, ao lado do método.

O trabalho que isto habilita — executar os scripts contra os motores — **ainda
não foi feito**. Enquanto não for, o repositório está numa posição pior que
antes em um aspecto: não há mais nem a checagem rasa. A dívida está registrada
no `TODO.md`, fases 2 e 3.

## Evidência no repo

- `platform/aws/network/versions.tf` — o provider sem condicional, sem `endpoints`
  e sem as flags de credencial fictícia.
- `scripts/_common.sh` — `check_env_arg` aceita só `develop` e `main`, com a
  mensagem de erro apontando para os motores locais.
- `platform/local/` — os motores que substituíram o emulador, ao lado de
  `platform/aws/`. A simetria é o ponto: são duas plataformas, e os mesmos
  workloads podem mirar qualquer uma.
- Nenhum `envs/local.tfvars` nem `backends/local.hcl` em lugar nenhum.
