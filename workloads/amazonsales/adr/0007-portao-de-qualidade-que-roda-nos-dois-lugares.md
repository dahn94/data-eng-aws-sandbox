# 0007 — Como ter um portão de qualidade que roda fora da AWS

**Status:** Aceito
**Data do registro:** 2026-08-29

## Contexto e problema

O [`adr/0005`](0005-onde-fica-o-portao-de-qualidade.md) decidiu **onde** o
portão de qualidade fica: antes da escrita, falhando o job para que o `Catch`
da máquina de estado interrompa a pipeline. Essa decisão não muda aqui.

O que muda é **com o quê** o portão é implementado, e o problema apareceu ao
tentar exercitá-lo fora da AWS.

O portão usava o Glue Data Quality: regras escritas em DQDL — o DSL do Glue —
avaliadas por `awsgluedq.transforms.EvaluateDataQuality`. Medido dentro da
imagem oficial `public.ecr.aws/glue/aws-glue-libs:5.0.10`, que é a que a
própria AWS publica para desenvolvimento local:

```
awsglue              OK
awsglue.context      OK
awsglue.transforms   OK
awsglue.dynamicframe OK
awsgluedq            FALTA
awsgluedq.transforms FALTA
```

A biblioteca não existe nem na imagem de desenvolvimento da AWS. Consequência:
**o portão de qualidade era a única parte da pipeline impossível de executar
fora da nuvem** — justamente a parte cujo comportamento mais importa verificar,
porque a afirmação do `0005` é sobre o que acontece quando uma regra reprova.

Antes desta decisão, a frase "o portão barra dado ruim" era uma alegação que
nada no repositório conseguia testar.

**Premissas que esta decisão assume:**

1. **A biblioteca substituta roda nos dois lugares.** Verificado: Great
   Expectations 1.21 avalia DataFrame do Spark dentro da imagem do Glue, e as
   regras do repositório têm tradução direta.
2. **As regras usadas são comuns**, não recursos exclusivos do DQDL. Verdadeiro
   hoje: existência de coluna, tipo, não-nulo, contagem, faixa de valor e
   proporção de unicidade.
3. **Perder a publicação de resultados no CloudWatch e no S3 é aceitável.** É
   perda real, e está nas mitigações.

## Requisitos que decidem

| Requisito | Valor exigido | Origem |
|---|---|---|
| O portão precisa falhar o job quando reprova | sim, sem exceção | [`0005`](0005-onde-fica-o-portao-de-qualidade.md) |
| O comportamento do portão precisa ser verificável | **sem depender de aplicar na AWS** | este ADR |
| Cobertura da biblioteca atual fora do runtime gerenciado | **nenhuma** | medido na imagem oficial |
| Regras exigidas | existência, tipo, não-nulo, contagem, faixa, unicidade | `dw-dims-...py`, `dw-facts-...py` |
| Publicação de métricas no CloudWatch | desejável, não exigida | — |

O requisito que decide é **verificabilidade sem AWS**. Uma regra de qualidade
que ninguém consegue exercitar é uma promessa, não um controle.

## Opções consideradas

1. **Manter o Glue Data Quality.** Zero trabalho, integração nativa com
   CloudWatch. Rejeitado porque mantém o portão como a única parte não
   testável do repositório, e porque o `0005` deixa de ter como ser defendido.
2. **Reescrever as regras como asserções em PySpark puro.** Sem dependência
   nenhuma, roda em qualquer lugar. Rejeitado por ser um passo atrás em
   expressividade: cada regra vira código imperativo, sem vocabulário comum e
   sem relatório.
3. **Great Expectations.** Roda nos dois lugares, tem vocabulário declarativo
   de regras, e é ferramenta de mercado — o que vale além deste repositório.
4. **Soda Core.** Equivalente em capacidade, checagens em YAML. Não foi testada;
   a escolha entre 3 e 4 é de familiaridade, não de capacidade.

## Decisão

Opção 3: o portão passa a usar Great Expectations, e o DQDL sai.

O requisito que pesou foi **verificabilidade sem AWS**. Entre um portão nativo
que ninguém testa e um portão portátil que se exercita a cada mudança, o
segundo protege mais — que é o propósito de um portão.

Ganho de desenho que veio junto: `run_data_quality_gate` deixou de receber
`GlueContext`. O portão agora opera sobre um DataFrame comum do Spark, então
não depende do Glue para nada — é o que o torna executável no
`platform/local/lakehouse`.

Isto **não** revisa o `0005`. Onde o portão fica, e o fato de ele falhar o job,
continuam como estavam.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Perde publicação automática no CloudWatch | **Não é contornado.** O Glue DQ enviava métricas por configuração; com GX, quem quiser métrica precisa emitir. Aceito: a alternativa era um portão não testável. |
| Perde `resultsS3Prefix`, o histórico de execuções no S3 | Não é contornado. O resultado aparece no log do job e a falha interrompe a pipeline — que é o comportamento de que o `0005` depende. |
| Dependência a mais no job Glue | `--additional-python-modules great_expectations==1.21.0`, fixado em `main.tf`. Custa alguns segundos no início do job. |
| A API do GX muda entre versões maiores | Por isso a versão é fixada, e não em faixa. A 1.x reformulou bastante a API em relação à 0.x. |
| `Uniqueness > 0.99` virou proporção de valores únicos | Tradução literal, e não unicidade estrita — o comportamento é o mesmo de antes, inclusive a tolerância. |

## Quando esta decisão se inverte

- **Quando `awsgluedq` passar a existir fora do runtime gerenciado**, na imagem
  oficial ou como pacote instalável. Aí o argumento central cai.
- **Quando uma regra exigida não tiver expressão em GX.** Nenhuma das atuais
  está nesse caso, mas o DQDL tem verificações estatísticas que o GX expressa
  de outro jeito ou não expressa.
- **Quando a publicação em CloudWatch virar requisito**, e não apenas
  desejável.

## Consequências

O portão de qualidade deixou de ser a única parte da pipeline que ninguém
conseguia executar. Verificado em execução, no lakehouse local: com dado bom o
portão deixa passar; com `user_id` nulo e duplicado ele barra, nomeando as duas
regras reprovadas e levantando `ValueError`.

Essa é a primeira vez que a afirmação do `0005` — "o portão falha o job e
interrompe a pipeline" — foi testada em vez de declarada.

O repositório passou a depender de uma ferramenta de fora do ecossistema AWS
por decisão, e não por acidente. Onde a AWS não oferece algo que rode
localmente, a preferência é uma alternativa de mercado — vale como aprendizado
além deste repositório e evita amarrar o desenho a um provedor.

O `dq_results_path` sumiu do `main.tf`, da máquina de estado e dos argumentos
dos jobs, porque não tem mais quem o consuma.

## Evidência no repo

- `workloads/amazonsales/scripts/glue_common.py` — a seção Data Quality, com o
  comentário registrando por que `awsgluedq` não serve.
- `workloads/amazonsales/scripts/dataeng-sandbox-amazonsales-dw-dims-s3tables-gdq.py`
  e `...-facts-...py` — os rulesets em GX, com a mesma cobertura do DQDL.
- `workloads/amazonsales/aws/infra/main.tf` — `additional_python_modules` fixando a
  versão do GX para o job na AWS.
- `platform/local/lakehouse/README.md` — o que a execução local cobre e o que
  não cobre.
