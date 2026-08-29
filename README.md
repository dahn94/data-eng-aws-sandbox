# data-eng-aws-sandbox

Um ambiente prático pra aprender engenharia de dados: um banco
transacional, captura de mudanças (CDC), streaming, processamento em lote e
ferramentas de BI, tudo rodando ou na AWS ou localmente via Docker. É um
repositório vivo — a ideia é continuar evoluindo com novas pipelines, sempre
focadas em AWS.

## ⚠️ Antes de tocar em qualquer coisa: isso custa dinheiro de verdade

A parte que roda na AWS (`workloads/` e `platform/`) usa recursos reais da sua conta
AWS. Não é caro se você seguir as instruções — **mas custa**. Antes do primeiro
`terraform apply`:

1. Crie um **AWS Budget** de alerta (grátis) — pelo console (Billing →
   Budgets) ou via CLI, ver [tutorial em `scripts/budget.md`](scripts/budget.md).
   Um orçamento de uns $10-20 com alerta em 50%/80%/100% já te avisa por
   e-mail, automaticamente, se algo ficar ligado sem querer.
2. Nunca deixe um `terraform apply` rodando "pra ver o que acontece" e vá
   fazer outra coisa. Aplique, estude, **destrua** (`terraform destroy`) ao
   terminar a sessão.

### Quanto cada peça custa se ficar ligada 24/7

Valores aproximados em `us-east-2`, para você saber o que está ligando:

| Módulo | Custo parado | Observação |
|---|---|---|
| `foundation` | ~US$0 | S3 cobra por armazenamento/requisição; centavos nos volumes de estudo |
| `network` | **US$0** | VPC, subnets, IGW e o Gateway Endpoint de S3 são gratuitos |
| `rds` | ~US$14/mês | `db.t4g.micro` + 20 GB. Pode ser parada. Free tier nos 12 primeiros meses |
| `dms` | ~US$28/mês | `dms.t3.micro`. **Não tem "stop", só delete** |
| `workloads/*` | ~US$0 parado | Glue cobra por execução (~US$0,44/DPU-hora). O de streaming cobra **enquanto roda** |
| `query-lambda` | ~US$0 parado | Lambda cobra por invocação |
| host do `webevents-streaming` | ~US$15/mês | EC2 `t4g.large` **spot** + 30 GB, só com `enable_streaming_host`. Sem `stop`: destrua |

Uma sessão de estudo típica (subir, mexer, destruir no mesmo dia) custa alguns
dólares. O risco não é o preço por hora, é esquecer ligado.

### Não precisa subir tudo

Cada root module tem state próprio, então você aplica **só o que o estudo do
dia precisa**. Perfis úteis:

| Quero estudar | Aplique | Custo/dia se esquecer ligado |
|---|---|---|
| Terraform, IAM, S3 | `foundation` | ~US$0 |
| Rede, Postgres, SQL | `+ network` `+ rds` | ~US$0,50 |
| Pipeline batch, Iceberg, Step Functions | `+ workloads/amazonsales` | ~US$0,50 |
| CDC de verdade | `+ dms` | ~US$1,40 |
| Streaming ponta a ponta | `+ workloads/webevents-streaming` com host e VPC ligados | ~US$3,60 |

As pipelines são as mais baratas de manter aplicadas: job Glue, Step Functions
e Lambda **não cobram nada parados**, só por execução. Quem cobra por hora é
RDS, DMS e a instância de laboratório — e um job de streaming enquanto roda.

### Três scripts para não esquecer ligado

```bash
./scripts/status.sh   [ambiente]   # o que está de pé agora e quanto custa
./scripts/pause.sh    [ambiente]   # para RDS e jobs Glue, mantendo os dados
./scripts/resume.sh   [ambiente]   # religa o que o pause parou
./scripts/teardown.sh [ambiente]   # destrói tudo, na ordem certa
```

O `status.sh` pergunta direto para a AWS, não para o state do Terraform — de
propósito. O state não sabe de um job de streaming em execução, e não enxerga
um ambiente que você aplicou de outra máquina.

Entre sessões de estudo, `pause.sh` costuma ser melhor que destruir: seus dados
continuam lá e você para de pagar a parte cara. Duas ressalvas: a AWS **religa
sozinha** uma instância RDS parada depois de 7 dias, e a **instância do DMS não
tem stop** — para ela, a única forma de parar de pagar é destruir.

O `teardown.sh` aceita `--dry-run`, pede confirmação digitada, e para os jobs
Glue em execução **antes** do `terraform destroy` — um run ativo não aparece em
nenhum state e continuaria cobrando.


A pasta `local-services/` (Kafka, OpenSearch, Metabase, Superset, ClickHouse) roda
100% local via Docker — essa parte não custa nada, só usa a RAM/CPU da sua
máquina.

## O que é este projeto, em uma frase

Um banco Postgres gera dados → alguma coisa captura as mudanças em tempo
real (CDC) → os dados viram um data lake organizado → você consulta e
visualiza esses dados. Esse é o ciclo que praticamente toda empresa de
dados roda de alguma forma, e é exatamente isso que este repositório deixa
você montar, quebrar e remontar sem medo.

## Glossário rápido

Se algum desses termos for novo pra você, volte aqui sempre que precisar:

| Termo | O que é, em uma frase |
|---|---|
| **RDS** | Banco de dados gerenciado pela AWS (aqui, um PostgreSQL). |
| **CDC** (Change Data Capture) | Capturar cada mudança (insert/update/delete) de um banco em tempo real, em vez de reconsultar tudo do zero. |
| **DMS** | Serviço da AWS que faz CDC do Postgres direto pro S3. |
| **Debezium / Kafka** | Alternativa a DMS: captura CDC e publica as mudanças em filas (tópicos) do Kafka, pra qualquer sistema consumir. |
| **Glue** | Serviço da AWS pra rodar jobs de processamento de dados (Spark por trás dos panos), tanto em lote quanto em streaming. |
| **Iceberg / S3 Tables** | Formato de tabela que faz um monte de arquivos no S3 se comportarem como uma tabela de banco de dados (com histórico, transações, etc.) — a base de um "data lakehouse". |
| **Step Functions** | Orquestrador da AWS: define a ordem em que vários jobs Glue devem rodar. |
| **OpenSearch** | Motor de busca/analytics em tempo real (primo do Elasticsearch) — aqui recebe o streaming de eventos. |
| **BI** (Business Intelligence) | Ferramentas pra transformar dados em dashboards/gráficos que alguém consegue olhar e entender (aqui: Metabase e Superset). |
| **DuckDB** | Banco analítico leve que roda embutido — aqui usado dentro de uma Lambda pra consultar o data lake sem precisar de um cluster. |
| **Terraform** | Ferramenta de "infraestrutura como código" — você descreve o que quer na AWS em arquivos `.tf`, ela cria/atualiza/destrói pra você. |

## Estrutura do repositório

O primeiro nível é organizado **por domínio, não por ferramenta**: o que você
faz com dado vem antes de com que ferramenta você faz. Por isso não existe uma
pasta `terraform/` — Terraform é detalhe de implementação, e amanhã pode entrar
dbt ou Flink sem que o workload precise se partir em três lugares.

Pelo mesmo motivo, `platform/` e `sources/` são separados: eles têm papéis
diferentes e ciclos de vida diferentes. Plataforma é consumida por quase tudo e
vive muito; fonte é onde o dado nasce, e só parte dos workloads depende dela.
Amontoar as duas esconderia justamente a informação que decide o que você
precisa aplicar antes de rodar um workload.

O que **não** ganha pasta no primeiro nível é infraestrutura de um consumidor
só. O `webevents-streaming` precisa de uma EC2 para hospedar Kafka e OpenSearch
onde a AWS os alcance — e essa EC2 mora dentro do workload, atrás de uma flag,
pela mesma regra que faz cada workload de Redshift criar o seu.

```
workloads/               # O QUE se faz com dado. Uma pasta por workload,
  amazonsales/           #   cada uma com state próprio e autossuficiente.
  webevents-streaming/   #   Nem todo workload é pipeline — veja a taxonomia
  dms/                   #   logo abaixo. É aqui que trabalho novo entra.
  query-lambda/
  federated-query/
  zero-etl/
  incremental-mv/
  data-sharing/

platform/                # O SUBSTRATO COMPARTILHADO. Vive muito, muda pouco.
  foundation/            #   Os buckets S3 que todo o resto usa. APLIQUE PRIMEIRO
  network/               #   VPC, subnets, rede — 5 dos 8 workloads consomem

sources/                 # DE ONDE O DADO VEM. Nem todo workload precisa:
  rds/                   #   Postgres transacional — 3 dos 8 consomem

modules/                 # Código compartilhado, nunca infraestrutura
                         #   compartilhada. Um workload instancia o módulo e
                         #   passa a ser dono do recurso que ele cria.

adr/                     # Índice geral das decisões e o método
local-services/          # Tudo que roda local (Docker), um por ferramenta
  streaming-cdc/         #   Kafka + Debezium
  search-opensearch/     #   OpenSearch + Dashboards
  bi-metabase/           #   Metabase
  bi-superset/           #   Apache Superset
  olap-clickhouse/       #   ClickHouse
  data-generator/        #   Script que gera eventos fake pro Postgres
  localstack/            #   Emulador da AWS — alvo de execução alternativo

scripts/                 # Utilitários de setup e governança de custo
                         #   (inclui budget.md: o alerta de orçamento que se
                         #   configura ANTES do primeiro apply)
.github/workflows/       # CI/CD do Terraform (um workflow reutilizável +
                         # um arquivo curto por root module)
```

Dentro de cada root module, os arquivos seguem a convenção usual: `main.tf`,
`variables.tf`, `outputs.tf` e `versions.tf`, com `envs/*.tfvars` e
`backends/*.hcl` por ambiente.

Cada pasta dentro de `workloads/`, `platform/` e `local-services/` tem seu
próprio `README.md` explicando exatamente o que ela faz e como rodar — este
README aqui é só o mapa geral.

### Nem todo caminho até o analytics é um pipeline

Pipeline é **uma** das formas de levar dado da fonte até quem consulta: a forma
procedural, em passos, na ingestão. Existem outras, e o que as separa é **quando
o trabalho acontece** e **se o dado é copiado**:

| Workload | Quando o trabalho acontece | Copia? | O que ele responde |
|---|---|---|---|
| [`amazonsales`](workloads/amazonsales/) | ingestão (batch) | sim | transformação pesada, modelagem, histórico |
| [`webevents-streaming`](workloads/webevents-streaming/) | ingestão (contínua) | sim | frescor de segundos num índice de busca |
| [`zero-etl`](workloads/zero-etl/) | contínuo, gerenciado | sim | replicar sem escrever nem operar código |
| [`dms`](workloads/dms/) | contínuo | sim | capturar mudança linha a linha do OLTP |
| [`incremental-mv`](workloads/incremental-mv/) | armazenamento | já copiado | agregado sempre pronto, sem job agendado |
| [`federated-query`](workloads/federated-query/) | consulta | **não** | juntar o estado de agora com o histórico |
| [`data-sharing`](workloads/data-sharing/) | consulta | **não** | entregar a outro time sem cópia nem export |
| [`query-lambda`](workloads/query-lambda/) | consulta | **não** | servir o lake por API, sem cluster |

Copiar compra histórico, isolamento da fonte e performance previsível. Não
copiar compra frescor, custo de ingestão zero e nada para operar — e cobra em
carga na fonte, latência imprevisível e, o mais caro, **ausência de histórico**:
se a origem faz `UPDATE` in-place, o passado morreu.

Em cada `workloads/*/README.md` a escolha aparece como um problema do dia a dia,
com os números que a decidiram em `nfr.md` e a decisão em `adr/`.

## Setup: duas coisas antes de qualquer terraform

**1. Defina seu prefixo de buckets.** Nomes de bucket S3 são globais na AWS
inteira, então os deste repositório não podem ser os mesmos que os de outra
pessoa. Rode uma vez, logo depois do clone:

```bash
./scripts/set-bucket-prefix.sh meu-usuario
```

Isso troca o placeholder `CHANGEME` em todos os `backends/*.hcl` e
`envs/*.tfvars`. Sem isso, `terraform init` falha.

**2. Baixe os jars.** Os jobs Glue e o Kafka Connect precisam de bibliotecas
que não ficam versionadas (são ~15 MB de binário):

```bash
./scripts/fetch-jars.sh
```

## Seu primeiro caminho, passo a passo

Não tente subir tudo de uma vez.

**1. Configure o básico**
```bash
git clone <url-do-seu-novo-repo>
cd data-eng-aws-sandbox
aws configure                # credenciais da sua conta AWS
aws sts get-caller-identity  # confirma que funcionou

./scripts/set-bucket-prefix.sh meu-usuario
./scripts/fetch-jars.sh
```

**2. Explore local primeiro (zero custo)**
Escolha um stack em `local-services/` e suba com `docker compose up -d` dentro da
pasta dele. Comece por `local-services/bi-metabase/` — é o mais simples de ver
funcionando. Os stacks que precisam de `.env` avisam no README deles.

**3. Crie os buckets**
```bash
cd platform/foundation
terraform init
terraform apply -var-file=envs/develop.tfvars
```
Este módulo roda com state **local** de propósito — ele cria o bucket que
serve de backend para todos os outros. Não apague a pasta.

**4. Suba a infraestrutura mínima na AWS**
```bash
cd ../network && terraform init -backend-config=backends/develop.hcl && terraform apply -var-file=envs/develop.tfvars

cd ../rds
export TF_VAR_rds_password='uma-senha-forte'
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars
```

Para conectar no banco da sua máquina, coloque seu IP em
`envs/develop.tfvars` (`allowed_cidr_blocks`) — o default é lista vazia,
ninguém entra de fora da VPC.

**5. Gere dados fake e veja o CDC funcionando**
`local-services/data-generator/` insere eventos continuamente no Postgres. Depois
suba `workloads/dms/` (ou `local-services/streaming-cdc/`) pra ver essas mudanças
sendo capturadas em tempo real.

O RDS já sobe com `rds.logical_replication = 1` — sem esse parâmetro, o CDC
faz a carga inicial e depois fica parado para sempre, sem erro claro.

**6. Processe os dados**
`workloads/amazonsales/` tem os jobs Glue que transformam os dados
brutos em tabelas organizadas (Iceberg) mais o Step Functions que orquestra
tudo; `workloads/webevents-streaming/` processa o streaming de
eventos web. `workloads/query-lambda/` consulta o resultado via DuckDB.

**7. Destrua o que não estiver usando**
```bash
./scripts/status.sh develop      # confere o que ficou de pé
./scripts/pause.sh develop       # pausa mantendo os dados, entre sessões
./scripts/teardown.sh develop    # ou destrói tudo, na ordem certa
```
`platform/network` pode ficar de pé entre sessões: VPC, subnets, Internet
Gateway e Gateway Endpoint de S3 não têm custo parado. O `foundation` também
pode ficar — deixe-o por último quando for limpar tudo, porque ele guarda o
state dos outros.

## Ambientes: dev, prod e local

Cada root module tem três ambientes, selecionados por
`-backend-config=backends/<amb>.hcl` e `-var-file=envs/<amb>.tfvars`:

| Ambiente | Vai para | Uso |
|---|---|---|
| `develop` | AWS (`dev`) | estudo do dia a dia |
| `main` | AWS (`prod`) | o mesmo, isolado |
| `local` | **LocalStack** | aplicar sem gastar nada — ver [`local-services/localstack`](local-services/localstack/README.md) |

A separação é real, não só de state: **todo recurso leva o ambiente no nome** e
os buckets de dados são separados (`...-raw-dev` / `...-raw-prod`). Dá para ter
os dois de pé na mesma conta AWS sem colisão de nome de IAM role nem um
sobrescrevendo os dados do outro.

O ambiente `local` usa o mesmo mecanismo: a variável `aws_endpoint_url`, vazia
por default, redireciona todas as chamadas para o LocalStack quando preenchida.
Nenhum código é duplicado para isso.

## Segredos e senhas

Nenhum módulo Terraform ou script tem senha com valor padrão. Você sempre
passa na hora de rodar:

```bash
export TF_VAR_rds_password='sua-senha-aqui'
export TF_VAR_opensearch_password='outra-senha-aqui'
```

Além disso:

- A senha do OpenSearch **não** vira argumento de job Glue (que ficaria em
  texto claro no console) — ela vai para o Secrets Manager e o job recebe só o
  ARN.
- Os stacks locais leem `.env`, que é ignorado pelo Git. Cada um tem um
  `.env.example` versionado com placeholders — copie e preencha.
- A CI autentica por **OIDC** (`secrets.AWS_ROLE_ARN`), sem chave de acesso de
  longa duração. O `apply` fica atrás de um GitHub Environment, então precisa
  de aprovação humana.
- O arquivo de plano do Terraform nunca é publicado como artifact: ele contém
  os valores das variáveis, senha inclusive.

## Pré-requisitos técnicos

- AWS CLI configurado com credenciais de uma conta com permissão pra criar
  os recursos acima
- Terraform >= 1.10 (usa lock de state nativo do S3 e `templatestring`)
- Docker e Docker Compose
- Python 3.9+ (pro `data-generator`)

## Roadmap

Este repositório nasceu de um treinamento e foi reorganizado pra crescer
como um projeto sério. A ideia é ir adicionando novos workloads aqui dentro
seguindo o padrão já estabelecido:

- **Workload novo** → uma pasta nova em `workloads/<nome>/`, com
  seu próprio `terraform.tf`, `variables.tf`, `main.tf`, `envs/`, `backends/`,
  `README.md`, `nfr.md` e `adr/` — e ganha state próprio. O workflow de CI dela
  é um arquivo de ~15 linhas que chama
  `.github/workflows/terraform-reusable.yml`. Copie a estrutura de
  `workloads/amazonsales/` se for um pipeline, ou a de
  `workloads/federated-query/` se não for.
- **Ferramenta local nova** → uma pasta nova em `local-services/<ferramenta>/`.
- **Infra-base nova** (não é workload nem ferramenta local) → avalie se
  cabe dentro de `platform/network`, `sources/rds` ou `workloads/dms`, ou
  se merece um root module próprio dentro de `platform/`.

Cada workload **possui** a infraestrutura que usa, inclusive quando isso
significa duas pastas criando cada uma o seu Redshift. É proposital: a pasta é
a unidade de estudo e precisa subir sozinha, com um comando, sem mapa mental de
pré-requisitos. O que não se duplica é **código** — o que dois workloads têm em
comum vira módulo em `modules/`.

Nunca amontoe um workload novo dentro do `main.tf` de outro — é exatamente
esse acoplamento que a separação em `workloads/` evita.

## Requisitos e decisões (NFRs e ADRs)

O que este README explica é **como** as coisas são. Por que elas são assim fica
em dois lugares, ao lado do código que justificam:

- **`nfr.md`** — os requisitos não-funcionais de cada fluxo de dados,
  quantificados em tabela: frescor, volume, retenção, garantia de entrega,
  recuperação, custo, quem opera. Documento vivo. Onde ainda não há medida, está
  escrito **"não medido"** — que é uma lista de tarefas honesta.
- **`adr/`** — as decisões, tituladas **pelo problema de dados**, não pela
  ferramenta. Cada ADR cita as linhas do `nfr.md` que pesaram, declara as
  **mitigações** dos seus pontos fracos (inclusive "não é contornado") e termina
  com **quando aquela decisão se inverte** — o gatilho observável que a derruba.

| Fluxo | Requisitos | Decisões |
|---|---|---|
| Ingestão por CDC | [`dms/nfr.md`](workloads/dms/nfr.md) | [`dms/adr/`](workloads/dms/adr/) |
| Lakehouse | — | [`foundation/adr/`](platform/foundation/adr/) |
| Pipeline batch | [`amazonsales/nfr.md`](workloads/amazonsales/nfr.md) | [`amazonsales/adr/`](workloads/amazonsales/adr/) |
| Pipeline streaming | [`webevents-streaming/nfr.md`](workloads/webevents-streaming/nfr.md) | [`webevents-streaming/adr/`](workloads/webevents-streaming/adr/) |
| Consulta federada | [`federated-query/nfr.md`](workloads/federated-query/nfr.md) | [`federated-query/adr/`](workloads/federated-query/adr/) |
| Replicação gerenciada | [`zero-etl/nfr.md`](workloads/zero-etl/nfr.md) | [`zero-etl/adr/`](workloads/zero-etl/adr/) |
| Estado declarativo | [`incremental-mv/nfr.md`](workloads/incremental-mv/nfr.md) | [`incremental-mv/adr/`](workloads/incremental-mv/adr/) |
| Entrega sem cópia | [`data-sharing/nfr.md`](workloads/data-sharing/nfr.md) | [`data-sharing/adr/`](workloads/data-sharing/adr/) |
| Camada de consulta | [`query-lambda/nfr.md`](workloads/query-lambda/nfr.md) | [`query-lambda/adr/`](workloads/query-lambda/adr/) |

Os quatro workloads do meio comparam caminhos diferentes **sobre o mesmo
dado** — o contrato que garante isso está em
[`workloads/DATASET.md`](workloads/DATASET.md).

Índice geral e o método em [`adr/`](adr/).
