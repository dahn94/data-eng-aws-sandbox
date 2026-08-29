# lab/ec2

Uma instância EC2 para hospedar os stacks de `local-services/` (Kafka,
OpenSearch) quando você quer que o job Glue de streaming, que roda na AWS,
consiga alcançá-los.

**Não faz parte do fluxo padrão.** Só aplique se souber por quê.

## ⚠️ Custo

| Configuração | Custo aproximado 24/7 |
|---|---|
| Default (`t3a.large` + 100 GB gp3) | **~US$65/mês** |
| `t3a.2xlarge` + 500 GB gp3 | **~US$260/mês** (~R$1.400) |

Uma instância EC2 é o item mais caro deste repositório e o mais fácil de
esquecer ligada. Se você só precisa dela por algumas horas, pare a instância
(`aws ec2 stop-instances`) — ao contrário do DMS, EC2 pode ser parada, e parada
você paga só o disco.

Ajuste `instance_type` e `root_volume_size` em `envs/*.tfvars` conforme a
necessidade real. O default é modesto de propósito.

## Aplicar

```bash
cd lab/ec2
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars
```

## Acesso

O default é **sem nenhuma porta aberta**. O acesso é por SSM Session Manager,
que não precisa de porta 22, de key pair nem de IP público:

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
```

Se preferir SSH, coloque seu IP em `envs/develop.tfvars`:

```hcl
ssh_allowed_cidr_blocks = ["203.0.113.10/32"]
key_name                = "nome-do-seu-key-pair"   # precisa já existir na conta
```

Para expor portas dos serviços (Kafka em 29092, OpenSearch em 9200) ao job
Glue ou à sua máquina, use `extra_ingress_rules` — sempre com CIDR restrito:

```hcl
extra_ingress_rules = [
  {
    description = "Kafka externo"
    from_port   = 29092
    to_port     = 29092
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.10/32"]
  },
]
```

## Detalhes

- A AMI é resolvida por `data.aws_ami` (Amazon Linux 2023 mais recente), não um
  ID fixo que expira e só existe numa região.
- `key_name` é opcional: vazio significa sem key pair.
- IMDSv2 é obrigatório na instância, e o disco raiz é criptografado.

## Destruir

```bash
terraform destroy -var-file=envs/develop.tfvars
```
