# workloads/amazonsales/local/scripts

O lugar da **solução local** deste workload — e ela ainda não existe.

Esta pasta não é espelho de `../../aws/scripts/`. O caminho AWS é o que o Glue
exige; aqui a escolha é livre, e o critério é otimização: qual motor, qual
formato e qual estratégia dão o melhor resultado para o mesmo problema, medido
contra o `../nfr.md`.

Candidatos que valem experimentar, e o que cada um testaria:

| Motor | O que ele questiona |
|---|---|
| DuckDB | se um processo único basta para este volume, sem cluster nenhum |
| Polars | se dá para trocar Spark por memória e vetorização |
| Spark aberto | se o ganho estava no Spark ou nas libs da AWS |
| dbt sobre DuckDB/Trino | se a transformação cabe em SQL declarativo |

Enquanto nada aqui existir, o DAG em `../dags/` dispara os jobs de
`../../aws/scripts/`. É ponto de partida, não destino: aquele código carrega
decisões que só fazem sentido no Glue.

**O que precisa ser igual, e o que pode divergir.** O resultado precisa ser
comparável — mesmo dataset de entrada (`../../aws/seed/`), mesmo star schema de
saída, mesmas regras de qualidade. O *como* é onde a busca acontece.
