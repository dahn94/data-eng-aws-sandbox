# workloads/zero-etl

**Replicar o banco transacional sem escrever nem operar código.** Você declara
uma integração entre o RDS e um Redshift; a AWS mantém as tabelas sincronizadas,
continuamente, para sempre. Nenhum job, nenhum agendamento, nenhum retry seu.

## A demanda

> *"Preciso das tabelas do sistema no warehouse. Todas. E atualizadas."*

Não é uma pergunta de negócio, é um pedido de infraestrutura — e é o pedido mais
comum que chega num time de dados. O analista não quer um pipeline; ele quer que
a tabela `orders` exista no lugar onde ele já sabe fazer `JOIN`, com o conteúdo
de hoje.

Quem pede não tem opinião sobre CDC, sobre `MERGE`, nem sobre janela de carga.
Quem pede quer a tabela lá.

## A resposta óbvia, e por que ela não serve

Escrever o pipeline de ingestão. É o que este repositório já faz duas vezes: o
`../dms/` captura mudança linha a linha e o `../amazonsales/` transforma e
modela.

O problema não é que a resposta óbvia esteja errada — ela funciona. O problema é
o que ela te torna:

1. **Você vira dono do transporte.** Schema mudou na origem? Seu job quebra.
   Coluna nova? Alguém precisa propagar. `ALTER TABLE` num domingo? Você
   descobre na segunda.
2. **Você vira dono do incremental.** Fazer `MERGE` correto, idempotente, com
   deleção e reprocessamento, é a parte cara e é onde os bugs moram.
3. **É esforço sem diferencial.** Copiar tabela A para o lugar B não é o
   trabalho que justifica um time de dados. É encanamento, e encanamento
   gerenciado é mais barato que encanamento próprio.

Quando o pedido é literalmente *"a tabela, como ela é, atualizada"* — sem
transformação, sem regra de negócio, sem histórico próprio — construir um
pipeline é escolher ser dono de um problema que a AWS já resolveu.

## O que você vai ver funcionando

Uma integração declarada em Terraform, e um `CREATE DATABASE` executado uma vez:

```hcl
resource "aws_rds_integration" "postgres_to_redshift" {
  source_arn = <arn do RDS>
  target_arn = <arn do namespace Redshift>
}
```

```sql
CREATE DATABASE zeroetl_origem FROM INTEGRATION '<integration_id>'
  DATABASE dataengsandbox;
```

Depois disso, as tabelas do Postgres aparecem no Redshift sozinhas — e continuam
aparecendo. Insira uma linha na origem, espere, consulte no destino:

```sql
-- no Postgres
INSERT INTO public.vendas VALUES (...);

-- no Redshift, minutos depois, sem nada ter rodado do seu lado
SELECT COUNT(*) FROM zeroetl_origem.public.vendas;
```

**O que medir** (vai para o [`nfr.md`](aws/nfr.md)):

- defasagem real entre origem e destino, medida por `MAX(pedido_em)` nos dois lados
- o que acontece com a integração quando a origem sofre `ALTER TABLE`
- custo do Redshift parado × custo do `../dms/` fazendo o mesmo trabalho

## O que isso te custou

**Você não transforma nada.** Chega o schema da origem, com os nomes da origem e
os erros de modelagem da origem. Se a tabela do OLTP tem `col_1`, `col_2` e uma
flag booleana guardada como `VARCHAR`, é isso que o analista vai encontrar.

**Você não tem histórico.** A integração mantém o destino igual à origem. Um
`UPDATE` in-place na origem sobrescreve o valor no destino também — o estado
anterior não existe em lugar nenhum. Quem precisa de "como estava em março"
continua precisando do `../dms/` e do lake.

**Você fica acoplado ao schema da origem.** Renomear coluna no OLTP é um evento
que atravessa a integração e chega no dashboard. Você não controla, e não é
avisado.

**É o workload mais caro do repositório.** O Redshift Serverless cobra por RPU
enquanto processa, com um mínimo de 4 RPU, e a integração faz o destino
trabalhar sozinho — inclusive quando ninguém está consultando. Diferente de
Glue e Lambda, que cobram por execução, este custo existe porque o warehouse
existe. **Faça `terraform destroy` ao terminar a sessão de estudo.**

**Você depende de uma restrição de versão.** Postgres ≥ 15.4 e destino Redshift
Serverless ou RA3. O `../../platform/aws/modules/rds` cria PG 17, então serve — mas isso é sorte
de configuração, não garantia.

Está quantificado em [`nfr.md`](aws/nfr.md) e decidido em
[`adr/0001`](aws/adr/0001-manter-uma-copia-fiel-do-oltp.md).

## Pré-requisitos

```bash
# 1. rede e Postgres (se ainda não estiverem aplicados)
cd platform/aws/network && terraform init -backend-config=backends/develop.hcl && terraform apply -var-file=envs/develop.tfvars
cd ../rds           && terraform init -backend-config=backends/develop.hcl && terraform apply -var-file=envs/develop.tfvars

# 2. este workload
cd ../../workloads/zero-etl
export TF_VAR_redshift_admin_password='...'   # 8-64 chars, maiúscula, minúscula e número
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars
```

O passo final é manual e não dá para automatizar em Terraform — o banco de
destino nasce de um comando SQL que cita o ID da integração recém-criada:

```bash
terraform output next_step   # traz o CREATE DATABASE já com o ID no lugar
```

## Destruir

```bash
terraform destroy -var-file=envs/develop.tfvars
```

A ordem importa dentro do próprio destroy: a integração fica pendurada na instância de
origem, e destruir o RDS primeiro deixa a integração órfã. O
`scripts/teardown.sh` já respeita essa ordem.

## Sem ambiente `local`

Não há ambiente local. Nada fora da AWS implementa integração zero-ETL nem
motor de Redshift — um apply contra o emulador validaria sintaxe de Terraform e
nada do comportamento que este workload existe para ensinar. Ver
`adr/0001` na raiz.

## Requisitos e decisões

- [`nfr.md`](aws/nfr.md) — os números
- [`adr/0001`](aws/adr/0001-manter-uma-copia-fiel-do-oltp.md) — como manter uma cópia fiel do OLTP sem virar dono do transporte
