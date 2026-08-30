# platform/local/services/orchestration-airflow

O orquestrador local, no lugar do Step Functions.

Orquestração é a única diferença entre AWS e local que **não é configuração**:
Step Functions e Airflow são produtos diferentes. Então a sequência é declarada
duas vezes — no `main.tf` do workload para a AWS, e num DAG para cá — enquanto
os jobs orquestrados continuam sendo **os mesmos arquivos**.

Os DAGs não moram aqui. Eles moram no workload que orquestram
([`workloads/amazonsales/local/dags/`](../../../../workloads/amazonsales/local/dags/)),
pela mesma razão que a Step Function mora no `main.tf` do workload: a sequência
pertence a quem é sequenciado. Aqui fica só o motor.

## Subir

```bash
docker compose up -d
docker compose logs airflow | grep -i password   # a senha do admin sai no log
```

Interface em `http://localhost:8090` (e não 8080, que o Trino já usa).

## Por que uma imagem própria

O `Dockerfile` acrescenta uma coisa só: o **cliente** do Docker. O DAG dispara
os jobs com `docker exec` no contêiner do lakehouse, e a imagem do Airflow não
traz o binário. O daemon continua sendo o da sua máquina, alcançado pelo socket
montado.

Instalar por `pip` como root é bloqueado pela imagem do Airflow — foi o que
derrubou a primeira tentativa. Por isso o que precisa vir de fora vem em tempo
de build.

## O que este ambiente não é

**Modo `standalone`:** um contêiner, banco embutido, sem Celery, sem Redis, sem
worker separado. Serve para ver a sequência rodar e falhar, que é o objetivo.
Não se parece com uma instalação de produção, e não deve ser lido como exemplo
de uma.

O que ele reproduz fielmente do Step Functions é o que importa para o desenho:
o encadeamento, o paralelismo, e o fato de uma tarefa falhada interromper o
resto — o mesmo contrato do `Catch` da máquina de estado.
