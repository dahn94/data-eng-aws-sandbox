# workloads/query-lambda

Uma Lambda com DuckDB que consulta as tabelas Iceberg do S3 Tables sem precisar
de cluster nenhum. Recebe uma query SQL e devolve JSON.

## Aplicar — são dois passos

A função roda a partir de uma imagem no ECR, e a imagem só pode ser publicada
depois que o repositório existe. Por isso o apply é em duas etapas:

```bash
cd workloads/query-lambda
terraform init -backend-config=backends/develop.hcl

# 1. cria o repositório ECR (image_tag vazio = função ainda não é criada)
terraform apply -var-file=envs/develop.tfvars

# 2. constrói e publica a imagem
cd scripts && ./build_and_push.sh
# ... imprime IMAGE_TAG=abc123def456

# 3. cria a função apontando para aquela imagem
cd .. && terraform apply -var-file=envs/develop.tfvars -var="image_tag=abc123def456"
```

A tag é o hash do conteúdo (Dockerfile + requirements + handler), e o
repositório é `IMMUTABLE`. Com `:latest` o Terraform nunca perceberia que a
imagem mudou e a função continuaria servindo o código antigo.

## Usar

```bash
aws lambda invoke --function-name "$(terraform output -raw function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload '{"query":"SELECT * FROM s3_tables_db.datawarehouse.dim_product LIMIT 10"}' \
  /dev/stdout
```

`catalog_arn` é opcional: sem ele a função usa a variável de ambiente
`DEFAULT_CATALOG`, que o Terraform já preenche com o lakehouse do ambiente.

## Segurança

Esta função **executa o SQL que recebe**, sem restrição. É o que a torna útil
como console de consulta, e é por isso que:

- A Function URL, quando criada, é sempre `AWS_IAM` — nunca `NONE`. Com `NONE`
  seria um executor de SQL aberto na internet.
- A URL só é criada se você pedir (`create_function_url = true`); o default é
  não criar.
- CORS só é configurado se você listar origens explícitas em `allowed_origins`.
  `["*"]` junto de credenciais é rejeitado pelos navegadores e é um antipadrão.
- A role da função é **somente leitura**, limitada ao bucket S3 Tables do
  ambiente. Uma query destrutiva não tem permissão para gravar nada.

## A imagem

As extensões do DuckDB (`aws`, `httpfs`, `parquet`, `avro`, `iceberg`) são
instaladas no **build**, não a cada cold start. Instalar em runtime deixava a
primeira invocação lenta, exigia saída para a internet e tornava a imagem não
reproduzível.

`requirements.txt` tem versão fixa pelo mesmo motivo.

## Custo

~US$0 parado. Lambda cobra por invocação e por GB-segundo; o ECR cobra pelo
armazenamento das imagens (a política de ciclo de vida mantém só as 5 mais
recentes).

## Requisitos e decisões

Requisitos não-funcionais em [`nfr.md`](nfr.md) — memória, disco efêmero e
timeout, que juntos definem o teto de escala desta abordagem.

- [`adr/0001`](adr/0001-servir-consulta-sem-cluster.md) — como servir consulta ao
  lakehouse sem manter um motor de query de pé. O requisito que decidiu foram os
  **2 GB de memória e 2 GB de disco**: é o que torna a solução barata e é
  exatamente onde ela deixa de servir.

Índice geral em [`adr/`](../../adr/).
