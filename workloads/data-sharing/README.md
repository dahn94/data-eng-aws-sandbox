# workloads/data-sharing

**Entregar dado a outro time sem criar uma segunda cópia.** Dois namespaces
Redshift, produtor e consumidor. O consumidor consulta as tabelas do produtor ao
vivo — sem export, sem job, sem defasagem, porque não há transporte.

## A demanda

> *"Dá pra mandar as vendas em CSV toda segunda?"*

O marketing quer analisar campanha contra receita. Eles têm as próprias
ferramentas, o próprio jeito de trabalhar, e não vão pedir acesso ao seu
warehouse — pediram um arquivo.

É o pedido mais fácil de atender e o mais caro de manter.

## A resposta óbvia, e por que ela não serve

Um pipeline de export: agrega, escreve o CSV, manda por e-mail ou joga num
bucket. Meia hora de trabalho.

O que acontece depois:

1. **Nasce uma segunda fonte da verdade.** A partir da terça, o número do
   marketing e o número do time de dados divergem. Ninguém sabe qual está certo,
   e a discussão vira reunião.
2. **O arquivo envelhece por definição.** Segunda 9h ele é verdade; quarta é
   história. Quem olha na quinta não sabe disso.
3. **Vira chamado recorrente.** "Não chegou." "Chegou vazio." "Dá pra incluir a
   coluna X?" "Dá pra mandar diário?" Cada pedido é meia hora, para sempre.
4. **Você exportou o dado, mas continua responsável por ele.** Se o CSV tem PII,
   ele agora está numa caixa de e-mail fora do seu controle — e a
   responsabilidade não foi junto com o arquivo.

O pedido parece ser sobre transporte ("mandar em CSV"). Não é. É sobre
**acesso**: o marketing quer poder olhar as vendas. Transporte foi só o único
mecanismo que eles conheciam para pedir isso.

## O que você vai ver funcionando

Do lado do produtor, o dado é publicado — não movido:

```sql
CREATE DATASHARE vendas_share;
ALTER DATASHARE vendas_share ADD SCHEMA public;
ALTER DATASHARE vendas_share ADD ALL TABLES IN SCHEMA public;
GRANT USAGE ON DATASHARE vendas_share TO NAMESPACE '<guid-do-consumidor>';
```

Do lado do consumidor, ele é montado — não copiado:

```sql
CREATE DATABASE vendas_do_time_de_dados
  FROM DATASHARE vendas_share
  OF NAMESPACE '<guid-do-produtor>';
```

E então, no warehouse do marketing:

```sql
SELECT COUNT(*), MAX(pedido_em)
  FROM vendas_do_time_de_dados.public.vendas;
```

**A prova de que não há cópia:** insira uma linha no produtor e repita a consulta
no consumidor. O `MAX` muda, e nenhum job rodou entre as duas execuções.
`terraform output proof_query` traz o roteiro pronto.

**O que medir** (vai para o [`nfr.md`](nfr.md)):

- defasagem entre escrita no produtor e leitura no consumidor (a expectativa é zero)
- latência da mesma query no produtor × no consumidor
- RPU consumida em cada lado — quem paga o quê
- o que o consumidor consegue fazer que não deveria (teste de permissão)

## O que isso te custou

**Dois warehouses ligados.** Este é o único workload do repositório que cria
duas instâncias de Redshift Serverless, cada uma com capacidade mínima de 4 RPU.
A demonstração exige duas pontas — não há como mostrar compartilhamento com um
namespace só. **É o item mais caro do repositório. Destrua ao terminar.**

**Só funciona entre iguais.** Mesma região, mesmo motor, mesma família de
serviço. O marketing que usa BigQuery, ou Excel, não é atendido por isto — e
esse é exatamente o caso em que o export volta a ser a resposta certa.

**O consumidor depende da sua disponibilidade.** Sem cópia, não há autonomia: se
o produtor cair ou for destruído, o consumidor lê nada. O CSV, com todos os seus
defeitos, sobrevive ao produtor. Isto não.

**Você continua dono — inclusive do que dá errado.** Um `DROP TABLE` no produtor
apaga o dado para os dois. Não existe mais uma cópia velha para salvar ninguém.

**Compartilhar não é o mesmo que governar.** O datashare concede acesso ao
objeto inteiro. Mascaramento por coluna, filtro por linha e auditoria de quem
leu o quê são outro problema, e ele não está resolvido aqui.

Está quantificado em [`nfr.md`](nfr.md) e decidido em
[`adr/0001-entregar-dado-sem-criar-uma-segunda-copia.md`](adr/0001-entregar-dado-sem-criar-uma-segunda-copia.md).

## Pré-requisitos

```bash
# 1. rede (se ainda não estiver aplicada)
cd platform/network && terraform init -backend-config=backends/develop.hcl && terraform apply -var-file=envs/develop.tfvars

# 2. este workload
cd ../../workloads/data-sharing
export TF_VAR_redshift_admin_password='...'   # 8-64 chars, maiúscula, minúscula e número
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars
```

Não precisa de fonte externa. Depende do seu orçamento: leia a seção de custo
acima antes de rodar o `apply`.

Para semear a tabela do produtor com volume de verdade, aponte
`seed_bucket`/`seed_prefix` no `envs/develop.tfvars` — o contrato está em
[`../DATASET.md`](../DATASET.md). Sem semente, o compartilhamento continua
demonstrável; só não há o que medir.

## Destruir

```bash
terraform destroy -var-file=envs/develop.tfvars
```

Dois workgroups cobrando por RPU. **Não deixe de pé entre sessões.**

## Sem ambiente `local`

Não há `envs/local.tfvars`. Datashare é um mecanismo do motor do Redshift, e o
LocalStack não tem motor de Redshift. Ver
[`../federated-query/adr/0002`](../federated-query/adr/0002-onde-o-emulador-deixa-de-ensinar.md).

## Requisitos e decisões

- [`nfr.md`](nfr.md) — os números
- [`adr/0001`](adr/0001-entregar-dado-sem-criar-uma-segunda-copia.md) — como entregar dado a outro time sem criar uma segunda cópia
