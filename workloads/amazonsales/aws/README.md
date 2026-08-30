# workloads/amazonsales/aws

A forma AWS deste workload. [`infra/`](infra/) tem o Terraform: os jobs Glue, a
máquina de estado do Step Functions, e os `envs/` e `backends/` de cada
ambiente.

```bash
cd infra
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars
```

O que **não** está aqui, de propósito:

- `../scripts/` — o código dos jobs. É o mesmo arquivo que roda no
  [`../local/`](../local/), e duplicá-lo por alvo seria o começo da divergência.
- `../seed/` — o semeador da origem, que também serve aos dois.
- `../adr/`, `../nfr.md` — as decisões e os números são do workload, não de um
  alvo.

A simetria com `../local/infra/` é o ponto: cada alvo declara a sua
infraestrutura, e tudo o que é do workload fica acima dos dois.
