#!/usr/bin/env bash
# Funções compartilhadas pelos scripts de operação do sandbox.
# Não execute diretamente — é carregado com `source`.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ordem de dependência: cada módulo depende dos anteriores.
# Aplicar é nesta ordem; destruir é na ordem inversa.
MODULES=(
  # Plataforma: o substrato compartilhado. Vive muito, muda pouco.
  "platform/foundation"
  "platform/network"
  # Fonte: de onde o dado vem. Só 3 dos 8 workloads dependem dela.
  "sources/rds"
  # Bancada: fora do fluxo padrão, nenhum workload depende.
  "lab/ec2"
  # Workloads: cada um é dono da infra que cria e sobe sozinho, desde que a
  # plataforma e a fonte de que ele depende estejam de pé (o README declara).
  "workloads/dms"
  "workloads/query-lambda"
  "workloads/amazonsales"
  "workloads/webevents-streaming"
  "workloads/federated-query"
  "workloads/zero-etl"
  "workloads/incremental-mv"
  "workloads/data-sharing"
)

PREFIX="dataeng-sandbox"

c_red()   { printf '\033[31m%s\033[0m' "$1"; }
c_green() { printf '\033[32m%s\033[0m' "$1"; }
c_yellow(){ printf '\033[33m%s\033[0m' "$1"; }
c_dim()   { printf '\033[2m%s\033[0m'  "$1"; }

die() { echo "erro: $*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' não encontrado no PATH."
}

# Traduz o nome do ambiente do repositório (develop/main/local) para o sufixo
# que aparece no nome dos recursos (dev/prod/local).
env_suffix() {
  case "$1" in
    develop) echo "dev" ;;
    main)    echo "prod" ;;
    local)   echo "local" ;;
    *)       echo "$1" ;;
  esac
}

check_env_arg() {
  case "$1" in
    develop|main|local) return 0 ;;
    *) die "ambiente inválido '$1'. Use: develop, main ou local." ;;
  esac
}

check_credentials() {
  aws sts get-caller-identity >/dev/null 2>&1 \
    || die "credenciais AWS não configuradas ou expiradas. Rode 'aws configure'."
}

# Um módulo só tem state se já foi aplicado alguma vez.
has_state() {
  local dir="$1" env="$2"
  if [[ "$dir" == *"/foundation" ]]; then
    [[ -f "$REPO_ROOT/$dir/terraform.tfstate" ]]
  else
    [[ -d "$REPO_ROOT/$dir/.terraform" ]]
  fi
}
