# workloads/incremental-mv/local

A forma local deste workload. Na AWS ele usa Redshift com `AUTO REFRESH`; não
existe Redshift em contêiner, então o que se exercita aqui é o **mecanismo**, em
ClickHouse.

O [`adr/0001`](../aws/adr/0001-servir-um-agregado-sempre-pronto.md) é sobre trocar
quem decide o "quando": você declara o resultado que deve valer sempre, e o
motor cuida de mantê-lo. Os dois motores fazem isso, por caminhos diferentes:

| | Redshift (AWS) | ClickHouse (local) |
|---|---|---|
| Quando recomputa | o motor escolhe, assíncrono | na escrita, incremental |
| Você agenda algo? | não | não |
| Custa parado? | sim, RPU | não |

A diferença de momento é real e está registrada: o ClickHouse não reproduz o
"não sei quando vai atualizar" do Redshift, que é justamente a contrapartida que
o ADR aceita. O que ele reproduz é o essencial — **ninguém agenda recomputação**.

## Rodar

```bash
docker compose -f ../../../platform/local/services/olap-clickhouse/docker-compose.yml up -d
docker exec -i clickhouse clickhouse-client --multiquery < materialized-view.sql
```

Depois, para ver o motor trabalhando sem você:

```sql
-- insira, e NÃO peça refresh nenhum
INSERT INTO vendas VALUES (1, 42, now(), 199.90, 'pago');

-- o agregado já está atualizado
SELECT hora, countMerge(pedidos) AS pedidos, sumMerge(receita) AS receita
  FROM receita_por_hora_dados GROUP BY hora ORDER BY hora;
```
