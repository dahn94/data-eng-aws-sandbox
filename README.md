# data-eng-aws-sandbox

Um ambiente prático pra aprender engenharia de dados: um banco
transacional, captura de mudanças (CDC), streaming, processamento em lote e
ferramentas de BI, tudo rodando ou na AWS ou localmente via Docker. É um
repositório vivo — a ideia é continuar evoluindo com novas pipelines, sempre
focadas em AWS.

## ⚠️ Antes de tocar em qualquer coisa: isso custa dinheiro de verdade

A parte que roda na AWS (pasta `aws-platform/`) usa recursos reais da sua conta
AWS. Não é caro se você seguir as instruções — **mas custa**. Antes do primeiro
`terraform apply`:

1. Crie um **AWS Budget** de alerta (grátis) — pelo console (Billing →
   Budgets) ou via CLI, ver [tutorial em `aws-platform/budget`](aws-platform/budget/README.md).
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
| `pipelines/*` | ~US$0 parado | Glue cobra por execução (~US$0,44/DPU-hora). O de streaming cobra **enquanto roda** |
| `query-lambda` | ~US$0 parado | Lambda cobra por invocação |
| `ec2` | **~US$65/mês** | `t3a.large` + 100 GB. Pode ser parada. Fora do fluxo padrão |

Uma sessão de estudo típica (subir, mexer, destruir no mesmo dia) custa alguns
dólares. O risco não é o preço por hora, é esquecer ligado.

### Não precisa subir tudo

Cada root module tem state próprio, então você aplica **só o que o estudo do
dia precisa**. Perfis úteis:

| Quero estudar | Aplique | Custo/dia se esquecer ligado |
|---|---|---|
| Terraform, IAM, S3 | `foundation` | ~US$0 |
| Rede, Postgres, SQL | `+ network` `+ rds` | ~US$0,50 |
| Pipeline batch, Iceberg, Step Functions | `+ pipelines/amazonsales` | ~US$0,50 |
| CDC de verdade | `+ dms` | ~US$1,40 |
| Streaming ponta a ponta | `+ ec2` `+ pipelines/webevents-streaming` | ~US$3,60 |

As pipelines são as mais baratas de manter aplicadas: job Glue, Step Functions
e Lambda **não cobram nada parados**, só por execução. Quem cobra por hora é
RDS, DMS, EC2 — e um job de streaming enquanto estiver rodando.

### Três scripts para não esquecer ligado

```bash
./scripts/status.sh   [ambiente]   # o que está de pé agora e quanto custa
./scripts/pause.sh    [ambiente]   # para RDS, EC2 e jobs Glue, mantendo os dados
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

```
aws-platform/            # Tudo que roda na AWS (Terraform), um "time" por pasta
  foundation/            # Os buckets S3 que todo o resto usa. APLIQUE PRIMEIRO
  network/               # Time de Plataforma: VPC, subnets, rede
  rds/                   # Time de Dados: o banco Postgres
  dms/                   # Time de Ingestão: captura de mudanças (CDC) pro S3
  pipelines/             # Uma pasta por pipeline de processamento, cada uma
    amazonsales/           # com seu próprio state — é aqui que pipelines
    webevents-streaming/   # novas entram conforme o projeto cresce
  query-lambda/          # Lambda/DuckDB que consulta o resultado das pipelines
  ec2/                   # Isolado, não faz parte do fluxo padrão
  modules/               # Peças reutilizáveis que os módulos acima usam

local-services/          # Tudo que roda local (Docker), um por ferramenta
  streaming-cdc/         # Kafka + Debezium
  search-opensearch/     # OpenSearch + Dashboards
  bi-metabase/           # Metabase
  bi-superset/           # Apache Superset
  olap-clickhouse/       # ClickHouse
  data-generator/        # Script que gera eventos fake pro Postgres
  localstack/            # Emulador da AWS — alvo alternativo do aws-platform/

scripts/                 # Utilitários de setup do repositório
.github/workflows/       # CI/CD do Terraform (um workflow reutilizável +
                         # um arquivo curto por root module)
```

Cada pasta dentro de `aws-platform/` e `local-services/` tem seu próprio `README.md`
explicando exatamente o que ela faz e como rodar — este README aqui é só o
mapa geral.

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
cd aws-platform/foundation
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
suba `aws-platform/dms/` (ou `local-services/streaming-cdc/`) pra ver essas mudanças
sendo capturadas em tempo real.

O RDS já sobe com `rds.logical_replication = 1` — sem esse parâmetro, o CDC
faz a carga inicial e depois fica parado para sempre, sem erro claro.

**6. Processe os dados**
`aws-platform/pipelines/amazonsales/` tem os jobs Glue que transformam os dados
brutos em tabelas organizadas (Iceberg) mais o Step Functions que orquestra
tudo; `aws-platform/pipelines/webevents-streaming/` processa o streaming de
eventos web. `aws-platform/query-lambda/` consulta o resultado via DuckDB.

**7. Destrua o que não estiver usando**
```bash
./scripts/status.sh develop      # confere o que ficou de pé
./scripts/pause.sh develop       # pausa mantendo os dados, entre sessões
./scripts/teardown.sh develop    # ou destrói tudo, na ordem certa
```
`aws-platform/network` pode ficar de pé entre sessões: VPC, subnets, Internet
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
como um projeto sério. A ideia é ir adicionando novas pipelines aqui dentro
seguindo o padrão já estabelecido:

- **Pipeline nova de processamento** → uma pasta nova em
  `aws-platform/pipelines/<nome>/`, com seu próprio `terraform.tf`,
  `variables.tf`, `main.tf`, `envs/`, `backends/` e `README.md` (copie a
  estrutura de `aws-platform/pipelines/amazonsales/` como ponto de partida) —
  ganha state próprio. O workflow de CI dela é um arquivo de ~15 linhas que
  chama `.github/workflows/terraform-reusable.yml`.
- **Ferramenta local nova** → uma pasta nova em `local-services/<ferramenta>/`.
- **Infra-base nova** (não é pipeline nem ferramenta local) → avalie se
  cabe dentro de `aws-platform/network`, `aws-platform/rds` ou `aws-platform/dms`, ou
  se merece um root module próprio no nível de `aws-platform/`.

Nunca amontoe uma pipeline nova dentro do `main.tf` de outra — é exatamente
esse acoplamento que a separação em `aws-platform/pipelines/` evita.
