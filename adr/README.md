# ADRs — registros de decisão de arquitetura de dados

Um ADR responde ao que o código não responde: **quais requisitos discriminavam
entre as opções, o que se aceitou perder, e sob que condições a resposta seria
outra.**

O método e o crédito de onde ele vem estão em [0000](./0000-adotar-adrs.md).

## Como estes ADRs são escritos

**O título é o problema, não a tecnologia.** "Como escolher uma linha por chave
quando o CDC entrega várias", não "dropDuplicates em vez de window function".
Cada problema tem sua própria heurística de decisão, e é ela que o documento
carrega.

**Os requisitos são quantificados e vivem no `nfr.md` do workload.** O ADR cita
as linhas que pesaram; quando um número muda, muda num lugar só. Custo é uma
linha dessa tabela, ao lado de frescor, volume, retenção e garantia de entrega —
quando custo vira o assunto, o problema de dados saiu de vista.

**Toda decisão declara as mitigações dos seus pontos fracos**, inclusive
"não é contornado", que é um risco aceito e explícito.

**Cada domínio numera do zero**, na pasta do que ele justifica, ao lado do
`nfr.md` correspondente.

## Índice

### Pipeline batch `amazonsales` — [`workloads/amazonsales/`](../workloads/amazonsales/)

Requisitos: [`nfr.md`](../workloads/amazonsales/nfr.md). Os ADRs seguem a ordem
do fluxo de dados, da entrada ao portão de saída.

| # | Problema | Requisito que decidiu |
|---|---|---|
| [0001](../workloads/amazonsales/adr/0001-contrato-de-schema-na-entrada.md) | Como impedir que uma mudança na origem entre calada | nenhum controle sobre a origem |
| [0002](../workloads/amazonsales/adr/0002-dedup-do-cdc-na-staging.md) | Como escolher uma linha por chave quando o CDC entrega várias | sem coluna de operação nem timestamp na origem |
| [0003](../workloads/amazonsales/adr/0003-modelagem-da-camada-analitica.md) | Como modelar a camada que o BI consulta | nenhum histórico de atributo exigido |
| [0004](../workloads/amazonsales/adr/0004-politica-de-recarga-por-camada.md) | Reconstruir a camada do zero ou atualizar só o que mudou | retenção de 30 dias do dado bruto |
| [0005](../workloads/amazonsales/adr/0005-onde-fica-o-portao-de-qualidade.md) | Onde fica o portão de qualidade em relação à escrita | nenhum consumidor em produção |
| [0006](../workloads/amazonsales/adr/0006-orquestracao-de-pipeline-batch.md) | Como orquestrar os jobs de uma pipeline batch | backfill não exigido; uma pessoa opera |

### Pipeline de streaming `webevents-streaming` — [`workloads/webevents-streaming/`](../workloads/webevents-streaming/)

Requisitos: [`nfr.md`](../workloads/webevents-streaming/nfr.md).

| # | Problema | Requisito que decidiu |
|---|---|---|
| [0001](../workloads/webevents-streaming/adr/0001-onde-descartar-dado-pessoal.md) | Em que ponto do fluxo o dado pessoal deixa de existir | nenhum dado pessoal exigido no destino |
| [0002](../workloads/webevents-streaming/adr/0002-semantica-do-destino-do-streaming.md) | Que pergunta o índice de destino consegue responder | at-least-once + `append` sem chave de documento |

### Ingestão por CDC — [`workloads/dms/`](../workloads/dms/)

Requisitos: [`nfr.md`](../workloads/dms/nfr.md).

| # | Problema | Requisito que decidiu |
|---|---|---|
| [0001](../workloads/dms/adr/0001-captura-de-mudancas-do-postgres.md) | Como levar as mudanças do Postgres ao lake, e com que semântica | um consumidor do evento |

### Lakehouse — [`platform/foundation/`](../platform/foundation/)

| # | Problema | Requisito que decidiu |
|---|---|---|
| [0001](../platform/foundation/adr/0001-semantica-de-tabela-no-s3.md) | Como dar semântica de tabela a arquivos soltos no S3 | três motores lendo as mesmas tabelas |

### Camada de consulta — [`workloads/query-lambda/`](../workloads/query-lambda/)

Requisitos: [`nfr.md`](../workloads/query-lambda/nfr.md).

| # | Problema | Requisito que decidiu |
|---|---|---|
| [0001](../workloads/query-lambda/adr/0001-servir-consulta-sem-cluster.md) | Como servir consulta ao lakehouse sem manter um motor de pé | 2 GB de memória e disco |

### Consulta federada — [`workloads/federated-query/`](../workloads/federated-query/)

Requisitos: [`nfr.md`](../workloads/federated-query/nfr.md).

| # | Problema | Requisito que decidiu |
|---|---|---|
| [0001](../workloads/federated-query/adr/0001-responder-sobre-o-estado-de-agora.md) | Como responder uma pergunta sobre o estado de agora | defasagem tolerada igual a zero |
| [0002](../workloads/federated-query/adr/0002-onde-o-emulador-deixa-de-ensinar.md) | Quando emular a nuvem para de ensinar sobre o dado | comportamento, não sintaxe, é o que se estuda |

### Replicação gerenciada — [`workloads/zero-etl/`](../workloads/zero-etl/)

Requisitos: [`nfr.md`](../workloads/zero-etl/nfr.md).

| # | Problema | Requisito que decidiu |
|---|---|---|
| [0001](../workloads/zero-etl/adr/0001-manter-uma-copia-fiel-do-oltp.md) | Como manter uma cópia fiel do OLTP sem virar dono do transporte | nenhuma transformação exigida no caminho |

### Estado declarativo — [`workloads/incremental-mv/`](../workloads/incremental-mv/)

Requisitos: [`nfr.md`](../workloads/incremental-mv/nfr.md).

| # | Problema | Requisito que decidiu |
|---|---|---|
| [0001](../workloads/incremental-mv/adr/0001-servir-um-agregado-sempre-pronto.md) | Como servir um agregado sempre pronto sem virar dono do agendamento | defasagem tolerada sem garantia contratual |

### Entrega sem cópia — [`workloads/data-sharing/`](../workloads/data-sharing/)

Requisitos: [`nfr.md`](../workloads/data-sharing/nfr.md).

| # | Problema | Requisito que decidiu |
|---|---|---|
| [0001](../workloads/data-sharing/adr/0001-entregar-dado-sem-criar-uma-segunda-copia.md) | Como entregar dado a outro time sem criar uma segunda cópia | uma única fonte da verdade |

### Método

| # | Problema |
|---|---|
| [0000](./0000-adotar-adrs.md) | Como registrar o raciocínio por trás das decisões de dados |

## Escrever um ADR novo

1. Copie [`template.md`](./template.md) para a pasta do que ele justifica.
2. Numere na sequência **daquela pasta**, começando em `0001`.
3. Titule pelo problema de dados, nunca pela ferramenta.
4. Preencha "Requisitos que decidem" **citando** o `nfr.md` do workload. Se o
   número que decide não estiver lá, acrescente-o lá primeiro — inclusive como
   "não medido", que é resposta honesta.
5. Preencha "Mitigações". "Não é contornado" é resposta válida e a mais útil.
6. Preencha "Quando esta decisão se inverte" com gatilho **observável**, ancorado
   num requisito. Não "se crescer", mas "quando o volume passar de X" ou "quando
   existir um segundo consumidor".
7. Acrescente a linha no índice acima.

Só decisão cara de reverter merece ADR: formato de dado, semântica de entrega,
modelagem, fronteira de privacidade, contrato entre módulos. Escolha reversível
em dez minutos não precisa de documento.

**ADR não se edita, se substitui.** Mudou a decisão? Escreva um novo, marque o
antigo como `Substituído por NNNN` e mantenha o texto original.

## O que estes ADRs revelaram

Escrevê-los produziu três achados que não estavam documentados em lugar nenhum:

1. **A ingestão descarta informação que a pipeline precisa.** O endpoint S3 do
   DMS não grava coluna de operação nem timestamp de commit, então delete é
   indistinguível de insert e não há ordem entre eventos da mesma chave. O item 1
   da Fase 01 do TODO começa **no módulo `dms`**, não na pipeline.
2. **A retenção de 30 dias do bucket raw torna a staging insubstituível.** A
   estratégia de recuperação declarada — "reexecutar do zero" — deixa de valer
   para ela a partir do dia 31, e a staging não tem backup próprio.
3. **Quase nada está medido.** Volume, duração de execução, latência de consulta,
   janela de exposição a dado reprovado: todos "não medido" nos `nfr.md`. Várias
   decisões corretas hoje repousam sobre suposições não verificadas.

## Backlog

Decisões já tomadas no repo que merecem ADR e ainda não têm:

| Problema | Onde |
|---|---|
| Onde limpar e tipar valor sujo — na entrada ou no consumo | `workloads/amazonsales/adr/` |
| Como escolher o grão de um fato, e como declará-lo | `workloads/amazonsales/adr/` |
| Como evitar divergência entre scripts de uma mesma pipeline (`glue_common`) | `workloads/amazonsales/adr/` |
| Como um job recebe segredo sem expô-lo (Secrets Manager × argumento de job) | `workloads/webevents-streaming/adr/` |
| Como versionar o schema de um tópico lido em runtime do Schema Registry | `workloads/webevents-streaming/adr/` |
| Como particionar as tabelas Iceberg (hoje: sem particionamento declarado) | `platform/foundation/adr/` |
