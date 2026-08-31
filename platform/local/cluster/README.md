# platform/local/cluster

O cluster Kubernetes local, declarado — o análogo do que `platform/aws/network`
é do lado da nuvem: o substrato onde tudo o mais é colocado.

```bash
./scripts/k8s-up.sh       # cria (idempotente) e fixa o contexto
./scripts/k8s-images.sh   # constrói o que falta e carrega no cluster
./scripts/k8s-down.sh     # destrói, PVCs inclusive
```

## Por que kind

`kind` roda os nós como contêineres no Docker que já existe na máquina — aqui,
o OrbStack. Não há VM nova: é uma camada dentro da que já está de pé, e o
cluster inteiro cabe num arquivo versionado (`kind.yaml`), que é o que permite
recriá-lo igual em outra máquina.

> **O OrbStack também tem um Kubernetes próprio**, e ele se anuncia como
> contexto `orbstack`. Se ele estiver ligado, vira o contexto corrente e um
> `helm install` distraído vai para o cluster errado, sem erro nenhum — foi o
> que aconteceu na primeira tentativa desta migração. Por isso o `k8s-up.sh`
> **fixa** o contexto em `kind-dataeng`, e vale conferir com
> `kubectl config current-context` antes de instalar qualquer coisa.

## O repositório dentro do nó

`kind.yaml` monta a raiz do repositório no nó, em `/repo`. É daí que os pods do
Spark leem **os mesmos arquivos** que o Glue executa na nuvem — sem cópia, e sem
reconstruir imagem a cada edição de script. É o equivalente do
`- ../../../..:/workspace:ro` que o Compose usava.

O caminho do repositório é da máquina, não do repositório: o `k8s-up.sh` expande
`${REPO_ROOT}` antes de entregar o arquivo ao `kind`.

## Acesso às interfaces

Nada é publicado em porta de host: quem quiser uma UI abre um túnel.

```bash
kubectl port-forward -n amazonsales svc/airflow 8090:8080     # Airflow
kubectl port-forward -n amazonsales svc/trino 8080:8080       # Trino
kubectl port-forward -n amazonsales svc/minio 9001:9001       # console do MinIO
kubectl port-forward -n incremental-mv svc/clickhouse 8123:8123
```

É uma peça a menos para operar que um ingress, e deixa explícito o que está
exposto e por quanto tempo.

## Três coisas que custaram tempo nesta migração

Estão registradas porque nenhuma delas dá um erro que aponte para a causa:

1. **O contexto errado.** O OrbStack sobe um Kubernetes próprio e o toma como
   corrente; um `helm install` distraído instala lá, com sucesso, e o cluster do
   kind fica vazio. O `k8s-up.sh` fixa o contexto — confira com
   `kubectl config current-context`.
2. **`helm dependency build` fotografa.** Os modelos entram em `charts/*.tgz` no
   momento do comando; editar um chart de `modules/` depois disso não muda nada
   no que o `helm upgrade` instala, e nada avisa.
3. **RBAC de `events`.** O `KubernetesPodOperator` assiste aos eventos do pod
   enquanto ele parte. Sem `events` no Role, ele leva 403 — e o `cleanup` do
   operador mascara isso reportando *"Pod ... returned a failure"* com o objeto
   de pod antigo, ainda em `Pending`. O sintoma é uma tarefa que falha enquanto
   o pod dela **termina com sucesso**. O chart do Airflow já concede a regra.

## O que os 16 GiB da VM impõem

Todos os motores ao mesmo tempo não cabem. Cada workload sobe no **seu**
namespace, e o certo é ter um de cada vez de pé:

```bash
helm list -A                                    # o que está instalado
helm uninstall amazonsales -n amazonsales       # devolve a RAM
```

Isso não é conselho de higiene — é o que a máquina permite, e é a mitigação
declarada no [ADR 0001](../adr/0001-isolar-o-dado-que-cada-workload-mede.md).
