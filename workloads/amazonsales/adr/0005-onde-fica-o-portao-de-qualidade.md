# 0002 — Onde colocar o portão de qualidade em relação à escrita

**Status:** Aceito
**Data do registro:** 2026-08-28
**Nota (2026-08-29):** a implementação do portão mudou do Glue Data Quality
para Great Expectations — ver [`0007`](0007-portao-de-qualidade-que-roda-nos-dois-lugares.md).
O que este ADR decide, *onde* o portão fica e o fato de ele falhar o job,
continua valendo.

## Contexto e problema

A pipeline valida os dados com Glue Data Quality: um ruleset para as dimensões,
outro para os fatos. A pergunta não é *se* valida — é **em que ponto do fluxo o
portão fica em relação à escrita da tabela**, porque isso decide o que ele
consegue impedir.

Um portão antes da escrita impede o dado ruim de existir. Um portão depois da
escrita só impede que ele se propague. São garantias diferentes, e a diferença
só aparece quando alguém pergunta "o que o BI está vendo agora?".

## Requisitos que decidem

| Requisito | Valor hoje | Origem |
|---|---|---|
| Consumidor em produção | **nenhum** | [`nfr.md`](../nfr.md) |
| Validação de valor | Glue Data Quality, depois da escrita | [`nfr.md`](../nfr.md) |
| Janela em que dado reprovado fica visível | **não medida** | [`nfr.md`](../nfr.md) |
| Recuperação após falha | reexecutar do zero | [`nfr.md`](../nfr.md) |
| Custo por execução | centavos | [`nfr.md`](../nfr.md) |

A linha que decide é **"consumidor em produção: nenhum"**. Ela é o que torna
tolerável uma janela em que a tabela publicada contém dado reprovado: não há
ninguém do outro lado para lê-la. Toda a validade desta decisão está pendurada
nessa única linha — e ela é a que tem mais chance de mudar.

A linha "janela não medida" é o buraco: ninguém sabe quanto tempo dura a
exposição, porque nunca foi cronometrada.

## Opções consideradas

1. **Sem portão.** DQ como relatório, sem falhar nada. Métrica bonita, zero
   efeito.
2. **Validar o DataFrame em memória, antes de escrever.** Barato e sem infra
   extra. Mas valida o que está para ser escrito, não a tabela resultante — não
   pega problema que só aparece depois do MERGE, e não vale para regra que
   depende do estado acumulado da tabela.
3. **Validar depois de escrever e falhar o job**, com a orquestração
   interrompendo o resto do fluxo.
4. **Write-audit-publish com branch do Iceberg.** Escrever numa branch, validar
   contra ela, e só fazer fast-forward para a `main` se passar. A tabela que o
   consumidor lê nunca chega a conter dado reprovado.

## Decisão

Opção 3, **assumidamente como estágio intermediário**.

Os jobs `*-gdq` avaliam o ruleset e dão `raise` quando alguma regra reprova.
Sem esse `raise`, o job terminava com sucesso mesmo com regra reprovada e a
pipeline ficava verde com dado ruim. Como a máquina de estado tem `Catch` em
cada estado, a falha interrompe a execução: **se a qualidade das dimensões
falhar, os fatos não são construídos.**

A força que decidiu foi a última: entregar a interrupção da propagação primeiro,
porque ela é a maior parte do benefício por uma fração do custo. A opção 4 é
reconhecidamente superior e está registrada como próximo passo — não como ideia
vaga, mas como item 3 da Fase 01 do TODO.

O que esta decisão **não** entrega, dito sem eufemismo: as dimensões já estão
gravadas quando o portão reprova. Entre a escrita e a reprovação existe uma
janela em que a tabela publicada contém dado que falhou na validação. Quem
consultar nesse intervalo lê dado ruim.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Dimensão reprovada fica publicada até o job de DQ falhar | **Não é contornado.** É o risco central, aceito porque não há consumidor |
| Nada sinaliza ao consumidor que a tabela está sob suspeita | **Não é contornado.** Não há flag, nem tabela de status, nem alerta |
| Propagação para os fatos | **É contornado**, e é o principal ganho: o `Catch` de cada estado interrompe a execução, então fato nenhum é construído sobre dimensão reprovada |
| Perder o histórico de qualidade | Contornado: resultados vão para o S3 curated e viram métrica no CloudWatch, independentes do log do job |
| Reverter uma escrita reprovada | Parcialmente: o snapshot anterior do Iceberg permite time travel, mas é manual e não há procedimento escrito |

## Quando esta decisão se inverte

- **Quando existir consumidor de verdade lendo a tabela.** Esse é o gatilho, e é
  binário: enquanto o único leitor é quem está desenvolvendo a pipeline, a
  janela entre escrever e reprovar não machuca ninguém. No instante em que um
  dashboard aponta para a tabela, ela passa a ser o problema principal e a opção
  4 deixa de ser refinamento e vira requisito.
- **Quando a reprovação exigir reversão manual.** Hoje, corrigir é reexecutar.
  Se alguma vez for preciso restaurar snapshot à mão para desfazer uma escrita
  reprovada, o custo do WAP já foi pago — só que em trabalho manual e sob
  pressão.
- **Se as regras passarem a depender do estado acumulado** (comparação com a
  carga anterior, detecção de desvio), a validação em branch fica ainda mais
  natural, porque dá para comparar branch e `main` diretamente.

## Consequências

- O ganho concreto é a **interrupção da propagação**: fato nenhum é construído
  sobre dimensão reprovada. É a maior parte do benefício de um write-audit-publish
  por uma fração do custo.
- A garantia que **não** se obtém é isolamento do consumidor. A tabela publicada
  pode conter dado reprovado durante uma janela que ninguém mediu.
- Existe histórico de qualidade fora do log do job — resultados no S3 curated e
  métricas no CloudWatch —, o que permite olhar a evolução em vez de só o último
  run.
- O portão custa uma execução de job Glue a mais por grupo de tabelas.
- A limitação já estava admitida no README da pipeline. Este ADR a transforma de
  nota de rodapé em decisão datada, com gatilho de revisão e mitigação declarada.

## Evidência no repo

- `workloads/amazonsales/scripts/glue_common.py:162-193` — o
  `run_data_quality_gate`, com o comentário explicando que sem o `raise` a
  pipeline ficava verde com dado ruim.
- `workloads/amazonsales/scripts/glue_common.py:128-159` — a
  avaliação do ruleset e a publicação de métricas.
- `workloads/amazonsales/README.md:60-62` — o `Catch` por estado
  interrompendo a execução.
- `workloads/amazonsales/README.md:64-67` — a limitação assumida,
  com o WAP nomeado como próximo exercício.
- `TODO.md` — Fase 01, item 3: o WAP com branch do Iceberg, que é a substituição
  prevista para este ADR.
