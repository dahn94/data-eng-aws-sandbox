# platform/foundation

**Este é o primeiro módulo que você aplica.** Ele cria os buckets S3 que todo o
resto do repositório assume que existem — inclusive o bucket que guarda o
*state* dos outros módulos.

## Por que este módulo tem state local

Todos os outros root modules guardam o state num bucket S3
(`backends/*.hcl`). Esse bucket precisa existir antes. Se o `foundation`
também usasse backend S3, ele dependeria do bucket que ele mesmo cria — um
ovo-e-galinha. Por isso aqui o state fica local, no arquivo
`terraform.tfstate` desta pasta (que o `.gitignore` já ignora).

Consequência prática: **não apague essa pasta**. Se perder o state local, o
`terraform destroy` não sabe mais quais buckets remover — você terá que
apagá-los pelo console.

## O que ele cria

| Bucket | Para quê |
|---|---|
| `<prefixo>-lake-configs` | tfstate dos outros módulos, scripts Glue, jars. **Compartilhado entre ambientes** (separados por *key*). |
| `<prefixo>-lake-raw-<amb>` | destino do DMS/Debezium, entrada das pipelines |
| `<prefixo>-lake-curated-<amb>` | resultados dos jobs de Data Quality |
| `<prefixo>-lake-logs-<amb>` | checkpoints do Spark Structured Streaming |
| `dataeng-sandbox-lakehouse-<amb>` | bucket **S3 Tables** onde as tabelas Iceberg vivem |

Os buckets de dados são separados por ambiente de propósito: assim `dev` nunca
escreve por cima de `prod`.

Todos vêm com criptografia habilitada e acesso público bloqueado. Os de dados
têm ciclo de vida de **30 dias** — num sandbox, dado bruto acumula sem ninguém
perceber e vira conta no fim do mês.

## Aplicar

Antes de tudo, defina seu prefixo de bucket (nomes de bucket são globais na
AWS inteira, então o prefixo tem que ser seu):

```bash
# na raiz do repositório, uma única vez
./scripts/set-bucket-prefix.sh meu-usuario
```

Isso troca o placeholder `CHANGEME` em todos os `backends/*.hcl` e
`envs/*.tfvars` do repositório. Depois:

```bash
cd platform/foundation
terraform init
terraform apply -var-file=envs/develop.tfvars
```

## Custo

Praticamente zero parado — S3 cobra por armazenamento e requisição. Com os
volumes de estudo deste repositório, centavos por mês. O bucket S3 Tables
também não tem custo fixo.

## Destruir

Deixe por último, depois de destruir todos os outros módulos (eles guardam o
state aqui dentro):

```bash
terraform destroy -var-file=envs/develop.tfvars
```

`force_destroy = true` é o default, então buckets com objetos dentro são
apagados junto. É o comportamento que se quer num sandbox, mas é também o
motivo de **nunca** apontar este módulo para uma conta com dado que importa.

## Decisões de arquitetura

- [`adr/0001`](adr/0001-semantica-de-tabela-no-s3.md) — como dar semântica de
  tabela a arquivos soltos no S3. O requisito que decidiu não foi o formato em
  si, foi **quem lê**: Spark, DuckDB e Athena sobre as mesmas tabelas.

Índice geral em [`adr/`](../../adr/).
