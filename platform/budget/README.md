# platform/budget

Não é um root module Terraform — é a rede de segurança que precisa existir
**antes** do primeiro `terraform apply` de qualquer outro módulo deste
repositório, então fica fora do IaC de propósito (o backend S3 do state nem
existe ainda nesse ponto).

## Configurando um AWS Budget de alerta (CLI)

Isso é rápido, é grátis, e é a única rede de segurança automática que avisa
por e-mail se você (ou um `terraform apply` esquecido) deixar algo ligado.
Precisa só do AWS CLI configurado (`aws configure`).

**1. Confirme sua conta e veja se já existe algum budget**

```bash
aws sts get-caller-identity --query Account --output text
aws budgets describe-budgets --account-id <seu-account-id>
```

Se o segundo comando não retornar nada, ainda não existe budget criado.

**2. Defina o orçamento**

```bash
cat > /tmp/budget.json <<'EOF'
{
  "BudgetName": "monthly-study-budget",
  "BudgetLimit": { "Amount": "15", "Unit": "USD" },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
EOF
```

Troque `"15"` pelo valor mensal que fizer sentido pra você.

**3. Defina os alertas por e-mail (50%, 80%, 100%)**

```bash
cat > /tmp/notifications.json <<'EOF'
[
  { "Notification": { "NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 50, "ThresholdType": "PERCENTAGE" },
    "Subscribers": [{ "SubscriptionType": "EMAIL", "Address": "seu-email@exemplo.com" }] },
  { "Notification": { "NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 80, "ThresholdType": "PERCENTAGE" },
    "Subscribers": [{ "SubscriptionType": "EMAIL", "Address": "seu-email@exemplo.com" }] },
  { "Notification": { "NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 100, "ThresholdType": "PERCENTAGE" },
    "Subscribers": [{ "SubscriptionType": "EMAIL", "Address": "seu-email@exemplo.com" }] }
]
EOF
```

Troque o e-mail pelo seu. Esse é o modo de **e-mail direto**
(`SubscriptionType: EMAIL`) — diferente de um subscriber via tópico SNS,
esse modo **não manda e-mail de confirmação nenhum**. O primeiro e-mail que
você recebe é literalmente o primeiro alerta de verdade, quando o gasto
real cruzar o threshold. Não chegou nada ainda? Normal, se o gasto real
ainda estiver em $0 — confirme com:

```bash
aws budgets describe-budget --account-id <seu-account-id> --budget-name monthly-study-budget --query 'Budget.CalculatedSpend'
```

**4. Crie o budget**

```bash
aws budgets create-budget \
  --account-id <seu-account-id> \
  --budget file:///tmp/budget.json \
  --notifications-with-subscribers file:///tmp/notifications.json \
  --region us-east-1
```

`--region us-east-1` é fixo aqui — a API do Budgets é global e sempre
atende nesse endpoint, independente de onde seus outros recursos estão
(no caso deste projeto, `us-east-2`).

**5. Confirme que ficou certo**

```bash
aws budgets describe-budget --account-id <seu-account-id> --budget-name monthly-study-budget
aws budgets describe-notifications-for-budget --account-id <seu-account-id> --budget-name monthly-study-budget
```

**6. Limpe os arquivos temporários**

```bash
rm -f /tmp/budget.json /tmp/notifications.json
```

**Editar ou remover depois:**

```bash
# Editar o valor do orçamento
aws budgets update-budget --account-id <seu-account-id> --new-budget file:///tmp/budget.json

# Remover o budget
aws budgets delete-budget --account-id <seu-account-id> --budget-name monthly-study-budget
```
