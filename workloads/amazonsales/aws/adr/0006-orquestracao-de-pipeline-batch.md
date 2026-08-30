# 0001 — Como orquestrar os jobs de uma pipeline batch

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

Esta pipeline tem oito jobs Glue com dependências reais entre si: staging antes
das dimensões, dimensões antes do portão de qualidade, portão antes dos fatos.

```
stg_table → [dim_product | dim_rating | dim_user] → dims_data_quality
          → [fact_product_rating | fact_sales_category] → facts_data_quality
```

Alguém precisa disparar os jobs na ordem, executar em paralelo o que é
paralelo, e **parar a execução quando um passo falha** — em especial quando o
que falha é o portão de qualidade, cujo propósito inteiro é impedir que o passo
seguinte aconteça.

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Tamanho do grafo | 8 jobs, dependências estáticas | [`nfr.md`](../nfr.md) |
| Paralelismo exigido | 3 dimensões, depois 2 fatos | [`nfr.md`](../nfr.md) |
| Frescor exigido | sob demanda, sem agendamento | [`nfr.md`](../nfr.md) |
| Backfill por intervalo de datas | **não exigido** | [`nfr.md`](../nfr.md) |
| Interrupção em falha | requisito de primeira classe (portão de DQ) | [`adr/0005`](./0005-onde-fica-o-portao-de-qualidade.md) |
| Quem opera | uma pessoa, em sessões | [`nfr.md`](../nfr.md) |
| Custo parado | US$0 | [`nfr.md`](../nfr.md) |

As duas linhas que decidem são **"backfill não exigido"** e **"quem opera: uma
pessoa"**. A primeira elimina a capacidade mais valiosa de um scheduler
dedicado; a segunda torna caro qualquer coisa que precise ser mantida de pé.
Custo parado entra como confirmação, não como critério: ele reforça a mesma
conclusão a que os requisitos de capacidade já chegaram.

## Opções consideradas

1. **Encadear dentro de um job Spark só.** Zero orquestração; perde-se
   paralelismo, granularidade de retry e a leitura do grafo. Uma falha no fim
   reexecuta tudo.
2. **Airflow gerenciado (MWAA) ou autogerenciado.** O padrão de mercado, com
   ecossistema enorme, backfill nativo e um catálogo de operadores. MWAA tem
   custo por hora do ambiente; autogerenciado tem custo de operação.
3. **Dagster.** Modelo orientado a *assets*, que casa bem com pipeline de dados
   e traz linhagem como subproduto. Mesmo custo estrutural de scheduler.
4. **Step Functions.** Serverless, cobra por transição de estado, `Catch`/`Retry`
   nativos por estado, integração direta com Glue.

## Decisão

Step Functions, com a definição como template JSON preenchido pelo Terraform.

A força que decide é **custo parado zero somado à ausência de operação**: nas
condições atuais — uma pipeline, oito jobs, grafo estático, sem backfill —
Airflow e Dagster ofereceriam capacidades que não seriam exercidas, cobrando por
elas em dinheiro (MWAA) ou em atenção (autogerenciado). Step Functions entrega
exatamente o que o grafo pede e desaparece quando não está rodando.

Duas decisões menores decorrem dela:

- **A definição é um template, não um JSON pronto.** Conta, região, ambiente,
  ARN do lakehouse e caminho de entrada entram por `template_variables` do
  Terraform. Assim o JSON versionado não carrega nome de bucket nem ID de conta
  — o mesmo arquivo serve `dev`, `prod` e `local`.
- **A role da máquina de estado só pode disparar os jobs desta pipeline**
  (`glue_job_arns` recebe só os jobs deste módulo), então uma pipeline não
  alcança a outra nem por engano.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Grafo em JSON, ruim de ler e revisar em diff | Parcialmente: o README da pipeline desenha o fluxo em texto, ao lado do JSON |
| Sem backfill parametrizado | Não é contornado — e não é exigido hoje |
| Adicionar job exige editar dois lugares (mapa e JSON) | Não é contornado; documentado no README como procedimento |
| JSON versionado poderia carregar conta e bucket | Contornado: os valores entram por `template_variables` do Terraform, então o arquivo não tem ARN nem nome de bucket |
| Máquina de estado poder disparar job de outra pipeline | Contornado: `glue_job_arns` recebe só os jobs deste módulo |
| Sem transferência de aprendizado para Airflow | Não é contornado — é o custo didático, e a razão de o item 8 da Fase 04 existir |

## Quando esta decisão se inverte

Três gatilhos concretos, nenhum verdadeiro hoje:

1. **Dependência *entre* pipelines, não só entre jobs de uma.** Enquanto cada
   pipeline é um grafo isolado, Step Functions basta. No dia em que a pipeline
   B tiver que esperar a A de outro state, aparece a necessidade de um
   agendador que enxergue as duas — e Step Functions não é bom nisso.
2. **Backfill parametrizado por intervalo de datas.** Reprocessar março inteiro
   em Airflow é uma linha de comando; aqui viraria lógica dentro da definição
   JSON, que é o pior lugar possível para lógica.
3. **Ordem de uma dezena de DAGs.** É quando o custo fixo de um scheduler se
   dilui e o ganho de ferramental (UI, catálogo de operadores, testes de DAG)
   passa a superá-lo.

O item 8 da Fase 04 do TODO existe para **medir** isso — refazer este mesmo
grafo em Airflow e em Dagster e escrever o veredito com números — em vez de
presumir. Até lá, esta decisão vale sob as condições listadas em "Forças", e não
como afirmação geral de que Step Functions é melhor que Airflow.

## Consequências

- O grafo de dependências é declarado e visível, com paralelismo real onde ele
  existe, em vez de encadeamento implícito dentro de um job só.
- O `Catch` por estado é o que **dá dente** ao portão de qualidade: sem ele, o
  job de DQ falharia e os fatos seriam construídos assim mesmo. Ver
  [0005](./0005-onde-fica-o-portao-de-qualidade.md).
- Não há UI de backfill, catálogo de operadores nem teste de DAG. Nenhum dos três
  é exigido hoje; todos passam a fazer falta assim que um dos gatilhos acima
  disparar.
- A orquestração não cobra nada entre execuções, o que mantém a pipeline
  aplicável entre sessões sem custo — confirmação de uma decisão tomada por
  outros motivos, não o motivo dela.

## ⚠️ Inferido

A decisão é evidência dura; as **opções consideradas** não. O repositório não
menciona Airflow, MWAA ou Dagster em lugar nenhum fora do TODO, que os cita como
estudo futuro e não como alternativa avaliada na época. A comparação acima foi
reconstruída a partir das forças observáveis no repo (custo parado, tamanho do
grafo, ausência de backfill). Se Step Functions entrou por ser o que o curso de
origem usava, esse é o motivo real e vale mais do que a reconstrução.

## Evidência no repo

- `workloads/amazonsales/aws/infra/main.tf:56-85` — a máquina de estado, os
  `template_variables` e a restrição da role aos jobs desta pipeline.
- `workloads/amazonsales/aws/scripts/step-functions-definitions/sfn_definition_s3tables_amazonsales.json`
  — a definição, com os `${...}` preenchidos pelo Terraform.
- `workloads/amazonsales/README.md:53-56` — o grafo de dependências.
- `workloads/amazonsales/README.md:60-62` — o `Catch` por estado
  como mecanismo de interrupção.
- `workloads/amazonsales/README.md:81-85` — o custo por execução,
  com nada cobrando parado.
- `README.md:33` — Glue e Step Functions com ~US$0 parado, contra RDS/DMS/EC2
  por hora.
