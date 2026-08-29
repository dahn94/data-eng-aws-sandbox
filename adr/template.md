# NNNN — <o problema, em uma frase>

**Status:** Proposto | Aceito | Substituído por [NNNN](./NNNN-....md)
**Data do registro:** AAAA-MM-DD

## Contexto e problema

Que pergunta de dados precisava de resposta, e em que situação. Descreva o
problema sem citar a solução — se o parágrafo só faz sentido depois de saber a
ferramenta escolhida, ele está escrito ao contrário.

Inclua as **premissas**: o que se está assumindo como verdadeiro e que, se for
falso, invalida a decisão.

## Requisitos que decidem

Os requisitos não-funcionais que efetivamente discriminam entre as opções —
**com número**, ou com "não medido" quando ainda não há número. Requisito sem
número costuma ser preferência disfarçada.

Custo é **uma linha desta tabela**, ao lado das outras. Quando ele vira o
assunto do ADR, o problema de dados sumiu de vista.

| Requisito | Valor exigido | Origem |
|---|---|---|
| Frescor | ... | `nfr.md` |
| Volume | ... | `nfr.md` |
| ... | ... | ... |

O valor de referência vive no `nfr.md` da pipeline, não aqui — este ADR cita as
linhas que pesaram na decisão. Quando o número mudar, ele muda lá, e este ADR
passa a ser candidato a revisão.

## Opções consideradas

1. **Opção A** — ...
2. **Opção B** — ...

## Decisão

O que foi escolhido, e **qual requisito pesou mais**. A decisão é consequência
dos requisitos acima; se não for possível apontar qual deles decidiu, o ADR
ainda não está pronto.

## Mitigações

A opção escolhida tem pontos fracos — admita quais são e registre **como cada um
é contornado hoje**, ou que não é. Um ponto fraco sem mitigação declarada é um
risco aceito, e isso também é informação.

| Ponto fraco | Como é contornado |
|---|---|
| ... | ... |

## Quando esta decisão se inverte

O gatilho concreto e observável que troca a resposta, ancorado num requisito do
`nfr.md`. Não "se o volume crescer", mas "quando o volume passar de X" ou
"quando existir um segundo consumidor do evento".

Esta seção é o que dá validade à decisão fora do contexto em que foi tomada, e é
a primeira a envelhecer — revise quando o `nfr.md` mudar.

## Consequências

O que passou a ser verdade por causa desta escolha, inclusive o que ficou pior e
não tem mitigação. ADR sem consequência negativa é propaganda, não registro.

## Evidência no repo

Onde a decisão está materializada, com `arquivo:linha`.

- `caminho/arquivo.py:12` — ...

## ⚠️ Inferido

Só quando o racional não está documentado em lugar nenhum e foi reconstruído a
partir do código. Diga exatamente o que é reconstrução, para quem revisa saber
onde olhar com desconfiança. Apague a seção quando não se aplicar.
