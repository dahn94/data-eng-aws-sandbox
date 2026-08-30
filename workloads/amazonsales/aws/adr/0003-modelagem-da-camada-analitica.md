# 0003 — Como modelar a camada que o BI consulta

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

A staging é uma tabela larga: 16 colunas misturando atributos de produto, de
usuário, de avaliação e valores de venda, com uma linha por review. É a forma
como o dado chega, não a forma como ele é consultado.

Quem consulta quer responder "quanto vendemos por categoria", "qual a nota média
por produto" — perguntas que agregam medidas e filtram por atributo. A pergunta
de arquitetura é qual formato dar a essa camada para que essas perguntas sejam
naturais de escrever e baratas de responder.

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Consumidores | Metabase / Superset, ad hoc; nenhum fixo | [`nfr.md`](../nfr.md) |
| Perfil de consulta | agregação por atributo (categoria, usuário, produto) | inferido do desenho dos fatos |
| Histórico de mudança de atributo | **nenhum** exigido hoje | [`nfr.md`](../nfr.md) |
| Volume | não medido | [`nfr.md`](../nfr.md) |
| Quem escreve as consultas | uma pessoa, mais ferramenta de BI | [`nfr.md`](../nfr.md) |

O requisito ausente é o mais determinante: **ninguém exige hoje saber como um
atributo era no passado.** É isso que torna aceitável um modelo sem histórico, e
é a linha que, mudando, derruba esta decisão.

## Opções consideradas

1. **Manter a tabela larga (one big table).** Zero modelagem; consulta simples
   para quem já conhece as colunas. Repete atributo de produto em toda linha e
   torna "lista de produtos distintos" uma agregação em vez de uma tabela.
2. **Modelo normalizado (3NF).** Sem redundância, ótimo para escrita — e para
   consulta analítica significa muitos joins.
3. **Star schema com chave natural.** Dimensões (`dim_product`, `dim_user`,
   `dim_rating`) derivadas por `distinct` da staging, fatos agregando medidas e
   referenciando as dimensões pelo id que já vem da origem.
4. **Star schema com chave substituta (surrogate key) e SCD Tipo 2.** O mesmo,
   com id sintético por versão e período de validade em cada linha da dimensão —
   o que permite perguntar "qual era a categoria deste produto em março".

## Decisão

Opção 3: star schema com **chave natural**, sem histórico.

O requisito que decide é a ausência de exigência de histórico. Entre 3 e 4, a
diferença não é qualidade de modelagem — é se o modelo precisa responder
perguntas sobre o passado. Como nenhum consumidor pergunta isso hoje, a chave
substituta seria maquinário sem uso, e maquinário sem uso é maquinário que
apodrece sem ninguém notar.

O star schema ganha de 1 e 2 pelo perfil de consulta: agregação por atributo é
exatamente o que ele otimiza, e é o que o BI gera.

Consequência de usar chave natural: `product_id` e `user_id` vêm da origem e
carregam o significado dela. Se a origem reaproveitar um id, ou mudar o formato
dele, a dimensão herda o problema sem intermediário.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Sem histórico: mudança de atributo apaga o valor anterior | **Não é contornado.** A tabela Iceberg guarda snapshots, então o valor antigo existe fisicamente e é recuperável por time travel — mas não é consultável como dimensão |
| Chave natural acopla o modelo à origem | Parcialmente: o contrato de schema ([0001](./0001-contrato-de-schema-na-entrada.md)) detecta mudança de tipo da coluna, mas não detecta reaproveitamento de id |
| Dimensão reconstruída por `distinct` herda erro da staging | O portão de qualidade ([0005](./0005-onde-fica-o-portao-de-qualidade.md)) roda sobre as dimensões antes de os fatos serem construídos |
| Fato sem chave de grão declarada | **Não é contornado.** O grão de cada fato está implícito no `groupBy`, não documentado |

A primeira linha merece atenção: **o histórico existe no Iceberg mas não no
modelo.** Snapshot serve para auditoria e recuperação, não para responder
"quanto vendemos na categoria que este produto tinha na época". São coisas
diferentes, e confundi-las é um erro comum.

## Quando esta decisão se inverte

- **Quando alguém precisar de uma resposta que dependa do passado do atributo** —
  "vendas pela categoria vigente na data da venda", "quantos usuários mudaram de
  faixa". É o gatilho único e claro: é a passagem para SCD Tipo 2, que exige
  chave substituta, colunas de vigência e um `MERGE` que fecha a versão anterior.
  É o item 1 da Fase 01 do TODO, e depende antes de
  [0002](./0002-dedup-do-cdc-na-staging.md) estar resolvido — não dá para
  versionar corretamente um histórico construído sobre eventos sem ordem.
- **Quando o volume tornar o `distinct` caro.** Reconstruir a dimensão inteira
  por `distinct` a cada execução é barato em volume pequeno e é a primeira coisa
  a doer quando cresce. O gatilho está em [0004](./0004-politica-de-recarga-por-camada.md).
- **Quando houver mais de uma origem para a mesma entidade.** Dois sistemas
  descrevendo o mesmo produto tornam a chave natural insuficiente, e a chave
  substituta deixa de ser luxo.

## Consequências

- Consultas de BI ficam naturais: agregar um fato e filtrar por atributo da
  dimensão, sem subconsulta.
- As dimensões são **derivadas**, não mantidas: existe uma única origem de
  verdade (a staging) e nenhum estado próprio a conciliar.
- Perde-se qualquer capacidade de análise histórica de atributo.
- O caminho para SCD2 está aberto, mas não gratuito: exige chave substituta,
  vigência, e a ordenação que hoje não existe.

## ⚠️ Inferido

A **decisão** é evidência dura — as tabelas, os `distinct` e os joins estão no
código. As **opções consideradas** não: o repositório não registra que one big
table, 3NF ou SCD2 tenham sido avaliados, e o histórico do Git foi consolidado num
commit único. A comparação foi reconstruída a partir do formato das tabelas e do
perfil de consulta que os fatos revelam. Em particular, atribuir a escolha à
ausência de exigência de histórico é leitura minha: é consistente com tudo no
repo, mas ninguém escreveu isso. Se o star schema veio do curso que originou o
projeto, esse é o motivo real e vale mais.

## Evidência no repo

- `workloads/amazonsales/aws/scripts/dataeng-sandbox-amazonsales-dw-dim-product-s3tables.py:12-21`
  — a dimensão derivada por `select(...).distinct()` da staging, com
  `product_id` natural como chave.
- `workloads/amazonsales/aws/scripts/dataeng-sandbox-amazonsales-dw-fact-sales-category-s3tables.py:8-25`
  — o fato: join com duas dimensões, `groupBy` e `sum` — o grão implícito no
  `groupBy`.
- `workloads/amazonsales/README.md:53-56` — o grafo staging →
  dimensões → fatos.
