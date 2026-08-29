# 0000 — Como registrar o raciocínio por trás das decisões de dados

**Status:** Aceito
**Data do registro:** 2026-08-28

## Contexto e problema

O repositório tem muita decisão de engenharia de dados tomada e materializada em
código: como deduplicar um fluxo de CDC, que formato de tabela usar, como
modelar a camada analítica, onde descartar dado pessoal, que semântica o destino
de um streaming tem. Os READMEs explicam **o que** cada peça faz e, em vários
casos, também **por quê**.

Falta o passo anterior: quais requisitos discriminavam entre as opções, e sob
que condições a resposta seria outra. Sem isso, uma decisão lida seis meses
depois vira dogma — ninguém sabe se continua valendo, porque ninguém sabe de que
ela dependia.

O problema é agravado por o histórico do Git ter sido consolidado num único
commit: não há mensagem de commit onde garimpar o raciocínio.

## Requisitos que decidem

| Requisito | Valor | Origem |
|---|---|---|
| Decisões que precisam de registro | as caras de reverter: formato de dado, semântica de entrega, modelagem, fronteira de privacidade | critério deste ADR |
| Custo de manutenção aceitável | baixo — documento que exige ritual morre | premissa |
| Quem revisa | uma pessoa | premissa do repo |
| Rastreabilidade exigida | poder ler a decisão antiga **junto** com a nova | critério deste ADR |

## Opções consideradas

1. **Continuar só com READMEs.** Já funciona parcialmente e custa zero. Mas
   README descreve o presente: quando a decisão muda, o texto anterior é
   sobrescrito e o raciocínio antigo desaparece.
2. **Seção "Decisões" dentro de cada README.** Mais perto do código, sem arquivo
   novo — e mistura dois públicos, quem quer rodar a coisa e quem quer entender
   por que ela é assim.
3. **ADRs em arquivos versionados, um por decisão**, imutáveis por convenção: uma
   decisão revista não é editada, é substituída por um ADR novo que aponta para o
   anterior.

## Decisão

Opção 3, com quatro convenções — cada uma resolvendo um modo de falha específico
de ADR mal escrito.

**1. O título é o problema, não a tecnologia.** "Como escolher uma linha por
chave quando o CDC entrega várias", não "dropDuplicates em vez de window
function". Título de ferramenta sugere um vencedor universal, que não existe:
cada problema tem sua própria heurística de decisão, e é ela que o documento
precisa carregar.

**2. Os requisitos que decidem são quantificados, e vivem fora do ADR.** Cada
pipeline tem um `nfr.md` com seus requisitos não-funcionais em tabela — frescor,
volume, latência, retenção, garantia de entrega, custo, quem opera — e o ADR
**cita** as linhas que pesaram, em vez de rederivá-las. Quando um número muda,
muda num lugar só, e os ADRs que dependiam dele viram candidatos a revisão.

Corolário que importa: **custo é uma linha dessa tabela, ao lado das outras.**
Quando custo vira o assunto do ADR, o problema de dados saiu de vista. Neste repo
custo aparece quase sempre como restrição operacional — o que se pode deixar
ligado — e quase nunca como o critério que escolhe entre duas arquiteturas.

**3. Toda decisão registra as mitigações dos seus pontos fracos.** Não basta
listar a consequência ruim: é preciso dizer como ela é contornada hoje, ou
declarar que não é. "Não é contornado" é resposta legítima e é a informação mais
útil que um ADR pode dar — é um risco aceito, explícito e datado.

**4. Cada domínio numera do zero, na pasta do que ele justifica.** O ADR sobre o
portão de qualidade do `amazonsales` mora em `workloads/amazonsales/adr/`, ao
lado do `nfr.md` dele. Mesma regra que o repo já aplica a README, state e CI:
cada pasta é dona do que é dela.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| ADR escrito depois da decisão racionaliza retroativamente | Contornado por uma seção `⚠️ Inferido` obrigatória sempre que as alternativas foram reconstruídas em vez de registradas na época |
| Um segundo lugar para manter atualizado | Contornado pela imutabilidade: não se atualiza um ADR, escreve-se outro |
| `nfr.md` desatualizado invalida os ADRs em silêncio | Parcialmente: cada `nfr.md` tem data de revisão e uma seção dizendo quais ADRs dependem de quais linhas |
| Sem revisor, a decisão é do próprio autor | **Não é contornado.** A palestra que inspirou este formato insiste em time de revisores; aqui há uma pessoa |
| Virar burocracia | Contornado pelo critério de entrada: só decisão cara de reverter |

## Quando esta decisão se inverte

- **Se o repositório passar a ter mais de um autor**, a numeração por pasta gera
  colisão em pull requests concorrentes — aí vale identificador com data. Com um
  autor, o problema não existe.
- **Se os `nfr.md` ficarem sistematicamente desatualizados**, o mecanismo de
  citação vira mentira e é pior do que rederivar os requisitos em cada ADR. O
  gatilho é a primeira vez que um ADR citar um número que já mudou.

## Consequências

- Toda decisão nova cara de reverter passa a custar ~30 minutos de escrita antes
  de virar código.
- A seção "Quando esta decisão se inverte" transforma cada ADR num gatilho de
  revisão ancorado num número, em vez de uma discussão reaberta do zero.
- Os `nfr.md` expõem quanto **não** está medido. Cada "não medido" é uma decisão
  tomada sobre suposição — desconfortável de ver escrito, e esse é o ponto.
- ADRs escritos depois das decisões carregam risco de racionalização, mitigado
  mas não eliminado pela seção `⚠️ Inferido`.

## Crédito

O formato — requisitos não-funcionais quantificados como *decision drivers*,
mantidos versionados junto do código, e ADRs que registram premissas, opções
escrutinadas e **mitigações para os pontos fracos da opção escolhida** — vem da
palestra "How To Actually Make Decisions When Architecting a Data Platform", de
Ed Freeman (endjin), no SQLBits.

O que **não** foi adotado, deliberadamente: a metade de seleção de produto e
fornecedor — matriz de avaliação pontuada, time multidisciplinar, envolvimento de
procurement e jurídico, análise de maturidade e funding de fornecedor. Aquilo
resolve escolha de plataforma corporativa. Aqui há uma pessoa, num repositório de
estudo já comprometido com AWS: não há fornecedor a avaliar nem stakeholder a
consultar, e montar a matriz seria encenação.

<https://endjin.com/what-we-think/talks/how-to-actually-make-decisions-when-architecting-a-data-platform>

## Evidência no repo

- `TODO.md` — a trilha paralela nomeia os ADRs como "o maior ganho, e de graça".
- `README.md:283-299` — a seção Roadmap já define regras de organização por
  pasta; os ADRs seguem a mesma regra.
