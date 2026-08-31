# 0001 — Como impedir que a execução de um workload altere o dado que outro mediu

**Status:** Aceito
**Data do registro:** 2026-08-31

## Contexto e problema

O [`DATASET.md`](../../../workloads/DATASET.md) enuncia a regra que torna os
números deste repositório comparáveis: *"o que garante a comparação não é
infraestrutura compartilhada, é dado idêntico"*. Cada workload é dono da
infraestrutura que usa — quatro Redshifts separados, três Postgres separados —
justamente para que o número de um não dependa do outro.

**Do lado AWS essa regra vale. Do lado local, não.** Os workloads com forma
local escrevem no mesmo MinIO, nos mesmos buckets e no mesmo catálogo Iceberg:
`sandbox-lake-raw-local/` e o namespace `datawarehouse` são estado global
mutável, um por máquina. Não há mecanismo que impeça a execução de um workload
de sobrescrever a tabela sobre a qual outro acabou de medir.

Isso não é hipotético para os números que já estão publicados: o `nfr.md` do
`amazonsales` reporta *"43,8 s, medido no Airflow"* e *"101 linhas na origem, 50
na staged — medido no ambiente local"*. São medidas tiradas de um ambiente que
qualquer outro workload pode alterar entre uma medição e a próxima, sem aviso e
sem deixar rastro.

O `container_name` global agrava: dois projetos Compose que subam a mesma peça
com o mesmo nome **roubam o contêiner um do outro** em silêncio. O `README.md`
de `platform/local` contorna isso com disciplina ("escolha um ponto de entrada e
fique nele") — ou seja, hoje a garantia é humana, não mecânica.

**Ressalva honesta:** nenhum requisito exige hoje dois workloads locais
simultâneos, e só dois dos oito têm forma local. O problema está declarado, e a
contaminação é possível; a frequência com que ela morde ainda é **não medida**.
Esta decisão é tomada com esse buraco à vista.

## Requisitos que decidem

| Requisito | Valor exigido | Origem |
|---|---|---|
| Base da comparação entre workloads | **dado idêntico**, versionado (`v1`) — nunca infra compartilhada | [`DATASET.md`](../../../workloads/DATASET.md) |
| Onde os números do `nfr.md` são medidos | **no ambiente local** (43,8 s; 101 → 50 linhas) | [`amazonsales/nfr.md`](../../../workloads/amazonsales/aws/nfr.md) |
| Donos do estado local hoje | **um** MinIO e **um** catálogo para todos os workloads | [`../README.md`](../README.md) |
| Isolamento entre execuções | por mecanismo, não por disciplina | esta decisão |
| Workloads com forma local | **2 de 8** hoje | árvore do repo |
| Execuções simultâneas | **não exigido hoje** | decisão registrada nesta sessão |
| Contaminação já observada | **não medida** | — |

O requisito que decide é o primeiro: **a comparação vive do dado, e o dado local
não tem dono.** Os demais não desempatam — eles dizem que a dívida ainda é
pequena, não que ela não existe.

## Opções consideradas

1. **Compose com parâmetros por workload.** Cada workload nomeia as suas peças e
   ajusta portas e versões (`parametros.env`). Resolve identidade e ajuste;
   **não isola estado** — os buckets e o catálogo continuam sendo um só.
2. **Compose com prefixo de bucket por workload.** Acrescenta `MINIO_BUCKETS` e
   um namespace Iceberg por workload. Barato e imediato, mas o isolamento passa a
   ser **convenção**: nada impede um script de escrever no prefixo do vizinho, e
   o `container_name` continua global.
3. **Kubernetes com Helm.** O chart é o modelo; o release num namespace é a
   instância. Dois workloads sobem o mesmo motor como dois releases, cada um com
   o seu Service, o seu PVC e o seu DNS — sem disputar nome nenhum.

## Decisão

Kubernetes com Helm, com um chart por motor em `platform/local/` e um release
por workload, no namespace do workload.

A força que decide é a **simetria com a regra do repo**: do lado AWS, "cada
workload é dono da infraestrutura que usa" é garantido por mecanismo — state
próprio, recursos próprios, ARNs próprios. A opção 3 é a única que dá ao lado
local a mesma garantia pelo mesmo tipo de mecanismo, em vez de por disciplina.

Ela também desfaz uma assimetria de vocabulário que hoje é real: `platform/aws/`
tem `modules/` porque Terraform tem modelos instanciáveis; `platform/local/` tem
`services/` porque um `docker-compose.yml` **não é instanciável** — incluído duas
vezes, ele funde em um serviço só, silenciosamente. Um chart é instanciável, e
com isso os dois lados passam a ter modelo e instanciação com o mesmo
significado.

A opção 1 já está no repositório (commit `409ac58`) e continua valendo: ela é o
que torna o ambiente atual utilizável enquanto esta decisão não estiver
implementada. A opção 2 foi descartada por trocar um isolamento inexistente por
um isolamento que depende de todo mundo lembrar do prefixo.

## Mitigações

| Ponto fraco | Como é contornado |
|---|---|
| Superfície operacional nova (cluster, charts, PVC, port-forward) | **Não é contornado** — é o preço. Mitigado só em parte por subir apenas o namespace do estudo do dia |
| O alvo AWS é Glue e S3 Tables, não EKS: o espelho fica menos literal | Parcial: o que se espelha passa a ser a *regra de propriedade* (chart↔módulo, namespace↔state), não o produto |
| Consumo de recursos na máquina de estudo | `requests`/`limits` declarados no chart, e um namespace por vez |
| O DAG perde o `docker exec` | Vira `KubernetesPodOperator` — que é mais fiel ao que orquestração faz em produção do que o `docker exec` era |
| Adia a verificação de comportamento de dado do `TODO.md` | **Não é contornado.** É trabalho de plataforma competindo com o trabalho que o plano chama de essencial |
| O requisito que motiva a decisão ainda não morde | **Não é contornado.** Está declarado acima como "não medido"; se continuar não mordendo, ver o gatilho de inversão |

## Quando esta decisão se inverte

- **Se em seis meses o repositório continuar com um workload local por vez e
  nenhum número de `nfr.md` tiver sido contestado por contaminação**, o
  isolamento por mecanismo não se pagou: o certo é voltar ao Compose com
  parâmetros (opção 1) e assumir a disciplina como suficiente. O gatilho
  observável é o par *(workloads com forma local, medições refeitas por
  contaminação)* — hoje **(2, não medido)**.
- **Se a operação do cluster passar a consumir mais sessões de estudo do que a
  engenharia de dados**, a decisão se inverte pelo mesmo motivo que o LocalStack
  saiu: a ferramenta virou o assunto. O gatilho é a razão entre commits de
  `platform/local/` e commits de `workloads/*/local/`.
- **Se o lado AWS ganhar um workload sobre EMR on EKS**, a decisão deixa de
  precisar de defesa: o espelho local passa a ser literal, e este ADR vira
  consequência daquele.

## Consequências

- `platform/local/services/` vira `platform/local/modules/`: a pasta passa a
  guardar modelos, e o nome deixa de ser uma imprecisão.
- O workload deixa de *incluir* peças e passa a *instanciar* releases — a mesma
  relação que `workloads/*/aws/infra` tem com `platform/aws/modules`.
- O `parametros.env` de cada workload vira o `values.yaml` dele.
- Nasce uma dependência de cluster local (**kind**, rodando sobre o Docker que
  já existe na máquina) e de Helm, que hoje não existe.
- Os números locais dos `nfr.md` passam a ser reprodutíveis por construção, e
  não por ordem de execução.

## Evidência

Medido nesta sessão (2026-08-31), com `docker compose config` e contêineres reais:

- **Instanciar duas vezes não dá duas instâncias.** Incluir o mesmo
  `services/trino/docker-compose.yml` duas vezes, com `env_file` diferente em
  cada entrada, rende **um** serviço com os parâmetros embaralhados
  (`container_name` do primeiro, porta do segundo) — sem erro e sem aviso.
- **Nome de contêiner é global, não do projeto.** Um `docker compose up` de um
  projeto chamado `amazonsales-local` recriou o contêiner de um projeto
  homônimo já existente na máquina, substituindo a imagem.
- **O nome do serviço continua resolvendo entre projetos** na rede compartilhada,
  e com duas instâncias no ar o DNS devolve **os dois IPs**, em round-robin
  silencioso.
- `platform/local/README.md` — o aviso "escolha um ponto de entrada e fique
  nele", que é a mitigação humana que este ADR quer substituir por mecanismo.
- Commit `409ac58` — a opção 1, implementada e verificada de ponta a ponta
  (oito tarefas do DAG em `success`, snapshot Iceberg novo).
