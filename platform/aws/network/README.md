# platform/aws/network

VPC, subnets públicas e privadas, Internet Gateway, tabelas de rota, o Gateway
Endpoint de S3 e o subnet group que o DMS usa. É o segundo módulo a aplicar,
depois do `foundation`.

## Aplicar

```bash
cd platform/aws/network
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars
```

## Desenho da rede

- **Subnets públicas** (2 AZs) — RDS e EC2. Rota `0.0.0.0/0` pelo Internet
  Gateway.
- **Subnets privadas** (2 AZs) — DMS. **Sem rota para a internet de
  propósito**: um NAT Gateway custaria ~US$32/mês parado, e o que roda ali só
  precisa alcançar o S3.
- **Gateway Endpoint de S3** — dá acesso ao S3 de dentro da VPC sem NAT e sem
  custo. Um *Interface* Endpoint para o mesmo serviço custaria ~US$15/mês
  parado e só faria sentido para acesso vindo de fora da VPC.

## Custo

**US$0 parado.** VPC, subnets, Internet Gateway, tabelas de rota e Gateway
Endpoint são todos gratuitos. Este módulo pode ficar de pé entre sessões de
estudo sem problema.

## Destruir

Destrua `rds`, `dms` e `ec2` antes — eles usam esta VPC.

```bash
terraform destroy -var-file=envs/develop.tfvars
```
