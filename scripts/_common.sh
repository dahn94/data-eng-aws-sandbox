#!/usr/bin/env bash
# Funções compartilhadas pelos scripts de operação do sandbox.
# Não execute diretamente — é carregado com `source`.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A plataforma é listada à mão, em ordem de dependência: o foundation cria o
# bucket de state que o resto usa, e a rede precisa existir antes de qualquer
# coisa que viva dentro dela.
PLATFORM_MODULES=(
  "platform/aws/foundation"
  "platform/aws/network"
)

# Os workloads são descobertos do filesystem: qualquer diretório em workloads/
# com um main.tf é um workload. Derivar em vez de listar é o que faz um workload
# novo entrar sozinho no status.sh, no pause.sh e — o que mais importa — no
# teardown.sh, onde esquecer uma linha significa deixar recurso cobrando sem
# nenhum aviso.
#
# A lista escrita à mão existia porque havia ordem entre workloads: dois deles
# penduravam recurso no Postgres compartilhado e precisavam ser destruídos
# antes dele. Desde que cada workload passou a criar a própria fonte, nenhum
# depende de outro, e a ordem entre eles deixou de importar — então a ordem
# alfabética do find serve.
# O Terraform de cada workload vive em <workload>/aws/infra. A pasta `local`
# ao lado dela é Docker, e não entra aqui: estes scripts operam a AWS.
WORKLOAD_MODULES=()
while IFS= read -r dir; do
  [[ -n "$dir" ]] && WORKLOAD_MODULES+=("${dir#"$REPO_ROOT"/}")
done < <(find "$REPO_ROOT/workloads" -mindepth 4 -maxdepth 4 -path '*/aws/infra/main.tf' -exec dirname {} \; 2>/dev/null | sort)

# ${arr[@]+"${arr[@]}"} em vez de "${arr[@]}": no bash 3.2 do macOS, expandir um
# array vazio sob `set -u` aborta o script.
MODULES=(
  ${PLATFORM_MODULES[@]+"${PLATFORM_MODULES[@]}"}
  ${WORKLOAD_MODULES[@]+"${WORKLOAD_MODULES[@]}"}
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

# Traduz o nome do ambiente do repositório (develop/main) para o sufixo que
# aparece no nome dos recursos (dev/prod).
env_suffix() {
  case "$1" in
    develop) echo "dev" ;;
    main)    echo "prod" ;;
    *)       echo "$1" ;;
  esac
}

# Só existem dois ambientes de Terraform. O `local` foi removido junto com o
# LocalStack: rodar local passou a ser subir os motores de verdade em
# platform/local/ e executar os scripts contra eles, sem Terraform no meio.
check_env_arg() {
  case "$1" in
    develop|main) return 0 ;;
    *) die "ambiente inválido '$1'. Use: develop ou main. (O ambiente 'local' não existe mais — veja platform/local/.)" ;;
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
