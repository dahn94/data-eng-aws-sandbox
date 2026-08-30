# 0001 — Em que ponto do fluxo o dado pessoal deixa de existir

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

O gerador de eventos web produz registros com bastante dado pessoal: endereço
IP, user agent, idioma do navegador, sistema operacional, tipo de dispositivo e
um identificador customizado de usuário. Esses campos entram no Postgres,
atravessam o CDC e chegam ao job de streaming junto com tudo o mais.

O índice de destino serve para análise de comportamento agregado — quantos
eventos por tipo, por período. Nenhuma dessas perguntas precisa saber o IP de
quem gerou o evento.

A pergunta é **em que ponto do fluxo esses campos param de existir**, e ela tem
respostas com propriedades muito diferentes: quanto mais tarde o descarte, mais
cópias do dado pessoal ficaram gravadas pelo caminho, cada uma com seu próprio
ciclo de vida, backup e controle de acesso.

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Dado pessoal exigido no destino | **nenhum** — as consultas são agregadas | [`nfr.md`](../nfr.md) |
| Campos pessoais na origem | 9 (IP, user agent, idioma, SO, dispositivo, id customizado) | [`nfr.md`](../nfr.md) |
| Controle de acesso do destino | usuário único de admin do OpenSearch | [`nfr.md`](../nfr.md) |
| Retenção no destino | **não declarada** — o índice não tem política | [`nfr.md`](../nfr.md) |
| Capacidade de apagar um registro específico | **não implementada** | [`nfr.md`](../nfr.md) |

O requisito que decide é o primeiro, e ele é categórico em vez de gradual:
**nenhuma consulta do destino precisa desses campos.** Quando o dado não é
necessário a jusante, a decisão deixa de ser sobre proteção e passa a ser sobre
por que ele ainda está sendo transportado.

As duas últimas linhas são o que torna o descarte tardio inaceitável: sem
retenção declarada e sem capacidade de apagar um registro, tudo que chega ao
destino tende a ficar lá para sempre.

## Opções consideradas

1. **Não descartar.** Índice completo, máxima flexibilidade analítica futura, e
   uma cópia permanente de dado pessoal num sistema com controle de acesso
   grosseiro.
2. **Descartar no destino**, por template de índice ou pipeline de ingestão do
   OpenSearch. O dado pessoal ainda trafega e passa pela memória do job.
3. **Mascarar ou tokenizar** em vez de descartar — hash do IP, por exemplo.
   Preserva a capacidade de contar usuários distintos sem guardar o
   identificador em claro.
4. **Descartar no job de streaming, antes da escrita.** O dado pessoal existe na
   origem e no tópico, mas não passa desse ponto.

## Decisão

Opção 4: uma lista explícita de colunas (`COLS_TO_DROP`) removida no fim da
transformação, antes de qualquer escrita.

O requisito que decide é "nenhum dado pessoal exigido no destino". Diante disso,
a opção 3 seria maquinário sem uso — tokenizar serve para preservar uma
capacidade analítica que ninguém pediu — e a opção 2 protegeria o mesmo dado num
ponto mais tardio, sem ganho.

A escolha de **descartar em vez de mascarar** é deliberada e vale registrar: dado
que não existe não vaza, não precisa de política de retenção e não aparece num
pedido de exclusão. Mascarar é a resposta certa quando a capacidade analítica é
necessária; descartar é a resposta certa quando ela não é.

Vale ser preciso sobre o alcance: isto **não** torna o fluxo conforme à LGPD. O
dado pessoal continua no Postgres, no WAL e no tópico do Kafka. O que a decisão
garante é que ele não se multiplica para dentro do sistema analítico.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Dado pessoal continua na origem e no tópico | **Não é contornado** aqui — é problema da camada de ingestão e da retenção do Kafka |
| A lista de colunas é manual: campo pessoal novo na origem passa direto | **Não é contornado.** Não há detecção automática de PII; é o item 6 da Fase 03 do TODO |
| Descartar é irreversível: análise futura que precise do campo não tem como voltar | Aceito — o dado continua na origem enquanto ela o retiver |
| Nada verifica que o descarte de fato aconteceu | **Não é contornado.** Não há teste nem checagem no índice |
| Controle de acesso grosseiro no destino | Mitigado indiretamente: como o dado sensível não chega lá, o controle grosseiro deixa de ser crítico |

A segunda linha é a mais perigosa: a proteção depende de alguém lembrar de
atualizar uma lista em Python quando a origem ganhar um campo novo. É
exatamente o modo de falha que a detecção automática de PII existe para cobrir.

## Quando esta decisão se inverte

- **Quando alguma pergunta legítima precisar distinguir usuários** — "quantos
  usuários únicos", "qual a taxa de retorno". Aí descartar deixa de servir e a
  resposta passa a ser a opção 3: tokenizar de forma consistente, o que preserva
  a contagem e não guarda o identificador.
- **Quando o destino passar a ter mais de um perfil de leitor.** Com uma persona
  só, descartar na borda basta; com duas, a pergunta vira controle de acesso por
  coluna, que é Lake Formation e é a Fase 03 do TODO.
- **Quando o número de campos pessoais crescer** a ponto de a lista manual não
  ser confiável. O gatilho prático é o primeiro campo pessoal que escapar
  despercebido — momento em que a detecção automática deixa de ser luxo.
- **Se o fluxo passar a pousar no lakehouse** (item 7 da Fase 03), a decisão
  precisa ser revisitada inteira: apagar dado de tabela Iceberg exige `DELETE`
  **mais** expiração de snapshot, e a estratégia de descarte na borda passa a ser
  ainda mais valiosa, porque evita o problema em vez de remediá-lo.

## Consequências

- Nenhum dado pessoal desses nove campos existe no sistema analítico. Não há o
  que proteger, expirar ou apagar lá.
- O índice não responde nenhuma pergunta por usuário individual, por navegador ou
  por dispositivo — e essa perda é permanente para os eventos já processados.
- A proteção é **código**, não configuração nem política: vive numa lista dentro
  do job, revisável em pull request, e quebra em silêncio se ninguém a atualizar.
- O job continua lendo o dado pessoal do tópico e trazendo-o para a memória. O
  descarte é de saída, não de leitura.

## Evidência no repo

- `workloads/webevents-streaming/aws/scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:23-35`
  — a lista `COLS_TO_DROP`, com o comentário que declara a intenção: colunas que
  "não interessam ao índice e que carregam dado pessoal", removidas antes de sair.
- `workloads/webevents-streaming/aws/scripts/dataeng-sandbox-webevents-streaming-kafka-opensearch.py:90`
  — o `drop` no fim da transformação, antes de qualquer escrita.
