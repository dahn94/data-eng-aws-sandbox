# localstack

Emulador da AWS rodando na sua máquina. Serve para aplicar o Terraform de
`aws-platform/` sem gastar nada e sem tocar numa conta real.

## Ele é diferente dos vizinhos desta pasta

Kafka, OpenSearch, Metabase e ClickHouse são **peças da arquitetura** — carregam,
guardam ou mostram dado. O LocalStack não: ele é um **alvo de execução
alternativo** para `aws-platform/`. Está aqui porque roda local em Docker, mas
a parte interessante da integração não é este compose — é o ambiente `local`
que cada root module ganhou.

## Subir

```bash
cd local-services/localstack
cp .env.example .env
$EDITOR .env          # cole seu LOCALSTACK_AUTH_TOKEN

docker compose up -d
curl -s http://localhost:4566/_localstack/health | jq
```

Tudo responde em `http://localhost:4566` — um gateway só, para todos os
serviços.

## Como o Terraform aponta para cá

O repositório já seleciona ambiente por `backends/<amb>.hcl` +
`envs/<amb>.tfvars`. O LocalStack é simplesmente um terceiro ambiente, ao lado
de `develop` e `main`:

```bash
cd aws-platform/foundation
terraform init
terraform apply -var-file=envs/local.tfvars

cd ../network
terraform init -backend-config=backends/local.hcl
terraform apply -var-file=envs/local.tfvars
```

Por baixo, `envs/local.tfvars` define `aws_endpoint_url = "http://localhost:4566"`.
Quando essa variável está preenchida, o provider ganha um bloco `endpoints`
apontando todos os serviços para o emulador, usa credenciais fictícias e
desliga as checagens que dependem de uma conta AWS real. Com ela vazia — que é
o default de `develop` e `main` — nada disso tem efeito e o comportamento
contra a AWS real é exatamente o de antes.

Duas diferenças propositais no ambiente `local`:

- **O prefixo de bucket é fixo (`sandbox`)**, não `CHANGEME`. No emulador não
  existe namespace global de bucket, então não é preciso rodar
  `scripts/set-bucket-prefix.sh` para usar só o LocalStack.
- **A região é `us-east-1`**, o default do LocalStack.

## Ordem de aplicação

A mesma da AWS real: `foundation` → `network` → `rds` → `dms` → pipelines. O
`foundation` continua com state local; os outros guardam o state no S3 **do
LocalStack** (`backends/local.hcl`).

## O que funciona

Com **LocalStack Pro** (que é o que o `docker-compose.yml` aqui espera), os
serviços que este repositório usa estão cobertos: S3, IAM, STS, EC2, RDS, DMS,
Glue, Step Functions, Lambda, ECR, CloudWatch Logs e Secrets Manager.

Duas ressalvas que valem mais do que a matriz de cobertura:

- **S3 Tables** é um serviço recente. Se o `foundation` falhar no
  `aws_s3tables_table_bucket`, confira a cobertura da sua versão do LocalStack
  — as pipelines Iceberg dependem dele.
- **Criar um job Glue ≠ executar um job Glue.** O LocalStack cria o recurso e
  aceita `StartJobRun`, mas rodar Spark de verdade com o catálogo Iceberg do
  S3 Tables é outra história. Para exercitar a lógica dos scripts, o caminho
  mais honesto é PySpark local; o LocalStack serve para validar a
  infraestrutura em volta.

Em resumo: ótimo para provar que o HCL está correto, que as permissões IAM
fecham e que a orquestração está ligada. Não substitui a AWS para estudar o
comportamento real de CDC e lakehouse.

## Encerrar

```bash
docker compose down       # mantém o estado (PERSISTENCE=1)
docker compose down -v    # apaga tudo
```

Se apagar o volume, apague também os `terraform.tfstate` locais do
`foundation` — senão o Terraform acha que os buckets ainda existem.
