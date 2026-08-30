# 0001 — Como servir consulta ao lakehouse sem manter um motor de query de pé

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

As tabelas Iceberg existem no S3 Tables. Falta o caminho de leitura: alguém
precisa executar SQL contra elas e devolver o resultado.

O reflexo comum é provisionar um motor de query — Athena, um cluster Trino, um
data warehouse. Mas o perfil de leitura aqui não é o que justifica esses
sistemas: consultas pontuais, resultado pequeno, sem concorrência, sem SLA.

A pergunta é qual a **menor** peça capaz de responder essas consultas — e onde
está a fronteira em que ela deixa de servir.

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Memória disponível ao motor | **2048 MB** | [`nfr.md`](../nfr.md) |
| Disco efêmero | **2048 MB** | [`nfr.md`](../nfr.md) |
| Tempo máximo de uma consulta | **900 s** (teto da Lambda) | [`nfr.md`](../nfr.md) |
| Concorrência exigida | não limitada, não medida | [`nfr.md`](../nfr.md) |
| Latência típica | **não medida** | [`nfr.md`](../nfr.md) |
| Maior resultado já retornado | **não medido** | [`nfr.md`](../nfr.md) |
| Permissão exigida | somente leitura, restrita ao lakehouse | [`nfr.md`](../nfr.md) |
| Custo parado | US$0 | [`nfr.md`](../nfr.md) |

O requisito que decide é o primeiro par: **2 GB de memória e 2 GB de disco.** Um
motor embutido processa tudo dentro de um processo só, então esse par é o
tamanho máximo do working set. É simultaneamente o que torna a solução barata e
o que define exatamente quando ela para de servir.

As três linhas "não medido" são o problema: **não se sabe quão perto do limite a
coisa está.** Uma decisão cuja validade depende de caber em 2 GB deveria ter a
medida de quanto se está usando.

## Opções consideradas

1. **Athena.** Serverless de verdade, sem nada para operar, integração nativa
   com Iceberg, escala bem além de 2 GB. Cobra por bytes escaneados e cada
   consulta é uma chamada de serviço com sua própria latência de partida.
2. **Cluster Trino ou similar.** Escala e concorrência reais; um cluster para
   manter de pé, contrariando a premissa de nada cobrar parado.
3. **DuckDB embutido numa Lambda.** O motor roda dentro do processo da função,
   lê Iceberg do S3, devolve o resultado. Nada de pé, custo por invocação, e o
   limite duro dos 2 GB.
4. **Não ter camada de consulta**, deixando cada ferramenta de BI se conectar
   sozinha. Empurra o problema para cada consumidor.

## Decisão

DuckDB embutido numa Lambda com imagem de container.

O requisito que decide é o perfil de consulta: resultado pequeno, sem
concorrência, sem SLA. Nesse regime, um motor embutido é estritamente mais
simples — não há serviço a chamar, não há resultado intermediário a materializar,
e a consulta acontece no mesmo processo que devolve a resposta.

Athena não perdeu por capacidade; perdeu por não trazer vantagem no perfil atual
e por cobrar por bytes escaneados num repositório em que o volume não está
medido. É a comparação que o item 8 da Fase 04 do TODO existe para fazer com
números, e este ADR não deve ser lido como veredito sobre ela.

A **role somente leitura, restrita ao bucket do lakehouse**, é parte da decisão e
não detalhe: uma função que executa SQL arbitrário precisa ser incapaz de
escrever.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Working set limitado a 2 GB | Parcialmente: memória e disco efêmero são variáveis do Terraform, então dá para subir até o teto da Lambda (10 GB) sem trocar de arquitetura |
| Teto de 900 s por consulta | **Não é contornado.** É limite duro da Lambda; consulta mais longa que isso exige outro motor |
| Sem medição de uso | **Não é contornado.** É a lacuna mais importante — as três linhas "não medido" do `nfr.md` |
| Consulta arbitrária numa função | Contornado: role somente leitura, restrita ao bucket do lakehouse |
| Empacotamento mais complexo (imagem de container, ECR) | Aceito: DuckDB e as extensões de Iceberg não cabem numa camada de Lambda |
| Sem cache entre invocações | Parcialmente: a Lambda reaproveita o ambiente em invocações próximas, mas isso não é garantia |

## Quando esta decisão se inverte

- **Quando uma consulta estourar memória ou os 900 s.** É o gatilho mais claro e
  ele se manifesta como erro, não como degradação — o que é bom: a falha é
  visível. A primeira reação é subir memória; a segunda, trocar de motor.
- **Quando houver concorrência real** — várias pessoas ou um painel consultando
  ao mesmo tempo. Cada invocação carrega seu próprio motor e relê os mesmos
  dados, sem cache compartilhado. Aí Athena passa a fazer mais sentido pelo mesmo
  motivo que hoje não faz.
- **Quando o volume das tabelas for medido e crescer uma ordem de grandeza.**
  Antes disso, a discussão é sobre suposições.
- **Quando o padrão de acesso virar interativo** — alguém explorando dado com
  latência importando —, porque partida a frio de Lambda é ruim para exploração.

## Consequências

- Existe caminho de leitura do lakehouse sem nada cobrando parado.
- O teto de escala é explícito e conhecido, em vez de descoberto em produção.
- A camada de consulta é um artefato de deploy próprio (imagem, ECR, versão da
  imagem), o que é mais empacotamento do que uma consulta de Athena exigiria.
- Vira um segundo leitor das tabelas Iceberg, ao lado do Spark — que é
  exatamente o requisito que decidiu o formato de tabela em
  [`foundation/adr/0001`](../../../../platform/aws/foundation/adr/0001-semantica-de-tabela-no-s3.md).

## ⚠️ Inferido

A decisão é evidência dura. As **opções consideradas** não: o repositório não
registra que Athena ou Trino tenham sido avaliados, e o histórico do Git foi
consolidado num commit único. A comparação foi reconstruída a partir do perfil de
uso que o código revela. Em particular, afirmar que Athena "não trouxe vantagem
no perfil atual" é reconstrução minha — pode ter sido escolha didática, para
exercitar DuckDB. Se foi, esse é o motivo real.

## Evidência no repo

- `workloads/query-lambda/README.md:3` — DuckDB consultando as tabelas Iceberg
  sem precisar de cluster.
- `workloads/query-lambda/README.md:53` — a role somente leitura, limitada ao
  bucket do lakehouse.
- `workloads/query-lambda/aws/infra/main.tf:55-57` — timeout de 900 s, 2048 MB de
  memória e 2048 MB de disco efêmero: o teto de escala, em números.
- `workloads/query-lambda/aws/infra/main.tf:53` — a imagem de container no ECR.
