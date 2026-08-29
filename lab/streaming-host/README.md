# lab/streaming-host

Uma instância **Graviton no spot** para hospedar os stacks de `local-services/`
(Kafka, Schema Registry, OpenSearch) num endereço que a AWS alcança — que é o
que o job Glue de `workloads/webevents-streaming` precisa e o seu `localhost`
não oferece.

**Não faz parte do fluxo padrão.** Só o `webevents-streaming` depende dela, e
só quando você roda esse workload contra a AWS de verdade.

## Custo

| Configuração | por hora | 24/7 |
|---|---|---|
| **Default: `t4g.large` spot + 30 GB** | **US$0,0171** | ~US$15/mês |
| `t4g.xlarge` spot + 30 GB (16 GB RAM) | US$0,0437 | ~US$34/mês |
| `t4g.large` **on-demand** + 30 GB | US$0,0672 | ~US$51/mês |
| O antigo `t3a.large` on-demand + 100 GB | US$0,0752 | ~US$65/mês |

Uma sessão de estudo de quatro horas custa **cerca de sete centavos de dólar**.

Dois descontos independentes se somam aqui:

- **Graviton** (`t4g` em vez de `t3a`) é qual processador: ARM feito pela AWS,
  ~11% mais barato. Exige que o software rode em `arm64` — todas as imagens
  Docker do `local-services` publicam `arm64`, então não há o que adaptar.
- **Spot** é como se paga: capacidade ociosa da AWS, ~70% mais barata.

## O que o spot custa em troca

**A instância não pode ser parada.** A requisição é `one-time`, então o ciclo é
criar e destruir, como a instância do DMS. Não existe `stop`/`start`.

**A AWS pode retomá-la com 2 minutos de aviso.** Quando isso acontece, a
instância é terminada e o que estava em Kafka e OpenSearch se perde. Para um
laboratório isso é aceitável, e tem um lado bom: obriga o conteúdo a ser
reconstruível pelo bootstrap em vez de virar um floco de neve.

O disco morre junto (`delete_on_termination`), então nada sobra cobrando depois.

## Aplicar

```bash
cd lab/streaming-host
terraform init -backend-config=backends/develop.hcl
terraform apply -var-file=envs/develop.tfvars
```

Depois, suba os serviços dentro dela — `local-services/streaming-cdc` e
`local-services/search-opensearch` — e aponte o `streaming_host` do
`workloads/webevents-streaming` para o IP público que sai em
`terraform output`.

## Acesso

O default é **nenhuma porta aberta**. O acesso é por SSM Session Manager, que
dispensa porta 22, key pair e IP público:

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
```

Para abrir as UIs no seu navegador **sem expor nada na internet**, encaminhe a
porta pelo próprio SSM:

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=5601,localPortNumber=5601"   # OpenSearch Dashboards
```

Se preferir acesso direto, coloque **o seu IP** em `envs/develop.tfvars`:

```hcl
allowed_cidr_blocks = ["203.0.113.10/32"]   # curl -s https://checkip.amazonaws.com
key_name            = "nome-do-seu-key-pair"  # opcional, só para SSH
```

Isso abre SSH e as portas de `service_ports` (Kafka 29092, Schema Registry 8081,
Connect 8083, kafka-ui 8080, OpenSearch 9200, Dashboards 5601) **apenas** para
esses blocos.

> **Nunca use `0.0.0.0/0`.** Kafka, Schema Registry e OpenSearch sobem sem
> autenticação nenhuma neste laboratório. Expostos na internet aberta, são
> encontrados por varredura automatizada em questão de horas.

## O ponto ainda em aberto: como o Glue chega aqui

O job Glue de `webevents-streaming` **não roda dentro da VPC** — o
`modules/glue-job` não declara nenhuma `aws_glue_connection`. Isso significa
que ele sai por IPs da AWS que você não tem como prever, e portanto não há CIDR
restrito que o deixe entrar.

Hoje existem dois caminhos, e nenhum é gratuito:

1. **Colocar o job dentro da VPC** (uma `aws_glue_connection` do tipo `NETWORK`
   apontando para a subnet privada). Aí o Glue alcança esta instância pelo IP
   **privado**, e o security group só precisa liberar o CIDR da VPC — nada fica
   exposto na internet. É a solução correta, e ainda não está implementada.
2. **Abrir as portas para `0.0.0.0/0`.** Funciona hoje, e é exatamente o que o
   aviso acima diz para não fazer.

Enquanto (1) não existir, esta instância serve para você mesmo rodar e inspecionar
os serviços a partir da sua máquina — o que já é útil — mas o job Glue em
`develop`/`main` ainda não fecha o circuito.

## Detalhes

- A AMI é resolvida por `data.aws_ami` e é **arm64**: uma AMI x86 não dá boot
  num `t4g`. Se trocar `instance_type` para família x86, troque o filtro da AMI
  em `main.tf` junto.
- IMDSv2 obrigatório e disco raiz criptografado.
- `key_name` é opcional; vazio significa sem key pair.

## Destruir

```bash
terraform destroy -var-file=envs/develop.tfvars
```

Como não há `stop` no spot, destruir é a única forma de parar de pagar — e é
barato recriar: o bootstrap reinstala tudo.
