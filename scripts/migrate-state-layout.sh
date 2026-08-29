#!/usr/bin/env bash
# Migra o state para o layout workloads/ + platform/ no bucket de configs.
#
#   ./scripts/migrate-state-layout.sh --check     # o que existe hoje, não escreve nada
#   ./scripts/migrate-state-layout.sh             # copia antigo -> novo
#   ./scripts/migrate-state-layout.sh --cleanup   # apaga o antigo (só depois de validar)
#
# O --check é diagnóstico: ele nunca falha por o repositório ainda não estar
# configurado. Se nenhum backend tiver prefixo de bucket definido, ele diz isso
# e sai com 0, sem sequer pedir credencial da AWS.
#
# O repositório passou de `aws-platform/<módulo>` para `workloads/<nome>` e
# `platform/<nome>`, e as chaves de state passaram a espelhar isso. O objeto no
# S3 não se move sozinho: este script copia, você valida com `terraform plan`, e
# só então apaga o antigo.
#
# Por que cópia e não `terraform init -migrate-state`: a cópia deixa o objeto
# antigo intacto. Se o plan de verificação vier sujo, você volta trocando a key
# de volta no backends/*.hcl — sem ter perdido nada.
#
# A ordem importa: copie ANTES de rodar `terraform init -reconfigure`. Ao
# contrário, o Terraform não acha state na key nova e se oferece para criar
# tudo do zero.
#
# `platform/foundation` não aparece aqui: ele roda com state local, em disco.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

MODE="copy"
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --cleanup) MODE="cleanup" ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)         die "argumento desconhecido: $arg" ;;
  esac
done

hcl_value() {
  local file="$1" key="$2"
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$file" | head -1
}

s3_exists() { aws s3api head-object --bucket "$1" --key "$2" >/dev/null 2>&1; }
s3_etag()   { aws s3api head-object --bucket "$1" --key "$2" --query ETag --output text 2>/dev/null; }

# Pré-varredura, antes de tocar na AWS: quantos backends já têm prefixo de
# bucket real. Um repositório recém-clonado tem todos em CHANGEME, e nesse caso
# não existe state em lugar nenhum — o --check precisa dizer isso, não morrer.
BACKENDS=()
while IFS= read -r hcl; do BACKENDS+=("$hcl"); done \
  < <(find "$REPO_ROOT/workloads" "$REPO_ROOT/platform" -mindepth 3 -maxdepth 3 -path '*/backends/*.hcl' 2>/dev/null | sort)

# O ambiente `local` fica de fora da contagem: ele aponta para o LocalStack, tem
# bucket de nome fixo e state efêmero — nunca há o que migrar nele, e incluí-lo
# faria um repositório recém-clonado parecer parcialmente configurado.
TOTAL=0; UNSET_PREFIX=0
for hcl in "${BACKENDS[@]}"; do
  [[ "$(basename "$hcl" .hcl)" == "local" ]] && continue
  b="$(hcl_value "$hcl" bucket)"
  k="$(hcl_value "$hcl" key)"
  [[ -n "$b" && -n "$k" ]] || continue
  TOTAL=$((TOTAL + 1))
  [[ "$b" == CHANGEME* ]] && UNSET_PREFIX=$((UNSET_PREFIX + 1))
done

# Copiar e apagar state exigem prefixo real em todos: migrar metade do
# repositório é pior do que não migrar nada.
if [[ $UNSET_PREFIX -gt 0 && "$MODE" != "check" ]]; then
  die "$UNSET_PREFIX de $TOTAL backends ainda estão com CHANGEME. Rode ./scripts/set-bucket-prefix.sh <prefixo> primeiro."
fi

if [[ "$MODE" == "check" && $UNSET_PREFIX -eq $TOTAL ]]; then
  echo
  echo "$(c_yellow "Os $TOTAL backends remotos ainda estão com o prefixo CHANGEME.")"
  echo
  echo "Isto não é um erro: significa que este clone nunca aplicou nada na AWS,"
  echo "então não existe state para migrar — nem no layout antigo, nem no novo."
  echo
  echo "Para começar:"
  echo "  ./scripts/set-bucket-prefix.sh <prefixo>"
  echo "  (cd platform/foundation && terraform init && terraform apply)"
  echo
  echo "Depois disso, este script vira rede de segurança: rode-o de novo e ele"
  echo "vai confirmar que cada módulo está no caminho novo."
  echo
  echo "Só leitura — nada foi alterado, e a AWS nem foi consultada."
  exit 0
fi

need aws
check_credentials

COPIED=0; SKIPPED=0; MISSING=0; PROBLEMS=0; MIGRATED=()
CHK_COPY=0; CHK_DONE=0; CHK_NONE=0; CHK_BOTH=0; CHK_UNSET=0

# Percorre todo backend declarado no repositório — assim um workload novo entra
# aqui sozinho, sem ninguém lembrar de editar uma lista.
while IFS= read -r hcl; do
  rel="${hcl#"$REPO_ROOT"/}"
  group_name="$(echo "$rel" | cut -d/ -f1-2)"   # ex: workloads/amazonsales
  env_file="$(basename "$hcl" .hcl)"            # develop | main | local
  name="$(echo "$rel" | cut -d/ -f2)"

  bucket="$(hcl_value "$hcl" bucket)"
  new_key="$(hcl_value "$hcl" key)"
  [[ -n "$bucket" && -n "$new_key" ]] || continue

  label="$group_name/$env_file"

  # Só sobra em modo check: os outros modos já morreram na pré-varredura.
  if [[ "$bucket" == CHANGEME* ]]; then
    echo "  $(c_dim "· $label — prefixo do bucket não definido, ignorado")"
    CHK_UNSET=$((CHK_UNSET + 1))
    continue
  fi

  # LocalStack: state efêmero num endpoint local. A key mudou no .hcl, mas não
  # existe objeto a migrar no bucket real.
  if [[ "$env_file" == "local" ]]; then
    [[ "$MODE" == "check" ]] && echo "  $(c_dim "· $label — LocalStack, nada a migrar")"
    continue
  fi

  env_dir="$(basename "$(dirname "$new_key")")"   # dev | prod

  # Dois formatos antigos possíveis, ambos sem o nível de grupo:
  #   plano:      terraform/dataeng-sandbox/<nome>/<env>/terraform.tfstate
  #   pipelines/: terraform/dataeng-sandbox/pipelines/<nome>/<env>/terraform.tfstate
  old_flat="terraform/${PREFIX}/${name}/${env_dir}/terraform.tfstate"
  old_pipe="terraform/${PREFIX}/pipelines/${name}/${env_dir}/terraform.tfstate"

  old_key=""
  for candidate in "$old_flat" "$old_pipe"; do
    if [[ "$candidate" != "$new_key" ]] && s3_exists "$bucket" "$candidate"; then
      if [[ -n "$old_key" ]]; then
        echo "  $(c_red '✗') $label — state antigo em DOIS lugares ($old_key e $candidate). Resolva à mão."
        PROBLEMS=$((PROBLEMS + 1))
        old_key=""
        break
      fi
      old_key="$candidate"
    fi
  done

  case "$MODE" in
    check)
      if [[ -n "$old_key" ]]; then
        if s3_exists "$bucket" "$new_key"; then
          echo "  $(c_yellow '!') $label — existe nos DOIS caminhos"
          CHK_BOTH=$((CHK_BOTH + 1))
        else
          echo "  $(c_yellow '→') $label — copiar de ${old_key#terraform/$PREFIX/}"
          CHK_COPY=$((CHK_COPY + 1))
        fi
      elif s3_exists "$bucket" "$new_key"; then
        echo "  $(c_green '✓') $label — já migrado"
        CHK_DONE=$((CHK_DONE + 1))
      else
        echo "  $(c_dim "· $label — nunca foi aplicado (sem state)")"
        CHK_NONE=$((CHK_NONE + 1))
      fi
      ;;

    copy)
      if [[ -z "$old_key" ]]; then
        if s3_exists "$bucket" "$new_key"; then
          echo "  $(c_green '✓') $label — já migrado"
        else
          echo "  $(c_dim "· $label — nunca foi aplicado, pulando")"
          MISSING=$((MISSING + 1))
        fi
        continue
      fi

      if s3_exists "$bucket" "$new_key"; then
        if [[ "$(s3_etag "$bucket" "$old_key")" == "$(s3_etag "$bucket" "$new_key")" ]]; then
          echo "  $(c_green '✓') $label — destino idêntico, pulando"
          SKIPPED=$((SKIPPED + 1))
        else
          echo "  $(c_red '✗') $label — destino JÁ EXISTE e é diferente. Não vou sobrescrever."
          PROBLEMS=$((PROBLEMS + 1))
        fi
        continue
      fi

      if aws s3 cp "s3://$bucket/$old_key" "s3://$bucket/$new_key" >/dev/null; then
        echo "  $(c_green '✓') $label — copiado"
        COPIED=$((COPIED + 1))
        MIGRATED+=("$group_name:$env_file")
      else
        echo "  $(c_red '✗') $label — falhou na cópia"
        PROBLEMS=$((PROBLEMS + 1))
      fi
      ;;

    cleanup)
      if [[ -z "$old_key" ]]; then
        echo "  $(c_dim "· $label — antigo já não existe")"
        continue
      fi
      if ! s3_exists "$bucket" "$new_key"; then
        echo "  $(c_red '✗') $label — o state NOVO não existe. Não apago o antigo."
        PROBLEMS=$((PROBLEMS + 1))
        continue
      fi
      if aws s3 rm "s3://$bucket/$old_key" >/dev/null; then
        echo "  $(c_green '✓') $label — antigo removido"
      else
        echo "  $(c_red '✗') $label — falhou ao remover"
        PROBLEMS=$((PROBLEMS + 1))
      fi
      ;;
  esac
done < <(printf '%s\n' "${BACKENDS[@]}")

echo
case "$MODE" in
  check)
    echo "A copiar: $CHK_COPY · já migrados: $CHK_DONE · sem state: $CHK_NONE · nos dois caminhos: $CHK_BOTH"
    [[ $CHK_UNSET -gt 0 ]] && echo "Ignorados por falta de prefixo: $CHK_UNSET"
    echo
    if [[ $CHK_COPY -eq 0 && $CHK_BOTH -eq 0 ]]; then
      echo "$(c_green 'Nada a migrar.') Nenhum state no layout antigo."
    else
      echo "Para migrar: ./scripts/migrate-state-layout.sh"
    fi
    echo
    echo "Só leitura — nada foi alterado."
    ;;
  copy)
    echo "Copiados: $COPIED · já ok: $SKIPPED · sem state: $MISSING · problemas: $PROBLEMS"
    if [[ ${#MIGRATED[@]} -gt 0 ]]; then
      echo
      echo "$(c_yellow 'PORTÃO') — valide CADA um antes de seguir:"
      echo
      for entry in "${MIGRATED[@]}"; do
        dir="${entry%%:*}"; envf="${entry##*:}"
        echo "  (cd $dir && terraform init -reconfigure -backend-config=backends/${envf}.hcl \\"
        echo "     && terraform plan -var-file=envs/${envf}.tfvars)"
      done
      echo
      echo "Cada plan tem que dizer \"No changes\". Se aparecer create ou destroy,"
      echo "PARE: o state antigo continua intacto, basta reverter a key no backends/*.hcl."
      echo
      echo "Só depois de todos limpos: ./scripts/migrate-state-layout.sh --cleanup"
    fi
    ;;
  cleanup)
    if [[ $PROBLEMS -gt 0 ]]; then
      echo "$(c_red 'Terminou com problemas') — revise acima."
    else
      echo "$(c_green 'Limpeza concluída.') O state agora vive só no layout novo."
    fi
    ;;
esac

[[ $PROBLEMS -eq 0 ]]
