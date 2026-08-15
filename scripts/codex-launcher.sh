#!/usr/bin/env bash
set -uo pipefail

workspace_home=${HOME:-/home/coder}
codex_install_dir=${CODEX_INSTALL_DIR:-$workspace_home/.local/libexec/codex}
codex_real="$codex_install_dir/codex"
codex_installer_url=${CODEX_INSTALLER_URL:-https://chatgpt.com/codex/install.sh}
codex_update_interval=${CODEX_AUTO_UPDATE_INTERVAL:-21600}
codex_failure_backoff=${CODEX_AUTO_UPDATE_FAILURE_BACKOFF:-900}
codex_update_timeout=${CODEX_AUTO_UPDATE_TIMEOUT:-120}
state_dir="$workspace_home/.cache/developer-workspace"
success_stamp="$state_dir/codex-update-success"
attempt_stamp="$state_dir/codex-update-attempt"
update_lock="$state_dir/codex-update.lock"

warn() {
  printf 'warning: %s\n' "$*" >&2
}

is_recent() {
  local path=$1
  local max_age=$2
  local now modified

  [[ -e "$path" && $max_age =~ ^[0-9]+$ ]] || return 1
  now=$(date +%s)
  modified=$(stat -c %Y "$path" 2>/dev/null || printf '0')
  ((now - modified < max_age))
}

install_codex() {
  local installer status legacy backup

  mkdir -p "$state_dir" "$codex_install_dir"
  installer=$(mktemp)

  if ! curl -fsSL --connect-timeout 10 --max-time 60 "$codex_installer_url" -o "$installer"; then
    rm -f "$installer"
    return 1
  fi

  if [[ ! $codex_update_timeout =~ ^[1-9][0-9]*$ ]]; then
    codex_update_timeout=120
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout "$codex_update_timeout" env \
      CODEX_HOME="$workspace_home/.codex" \
      CODEX_INSTALL_DIR="$codex_install_dir" \
      CODEX_NON_INTERACTIVE=1 \
      CODEX_RELEASE=latest \
      PATH="$PATH:$codex_install_dir" \
      sh "$installer"
  else
    env \
      CODEX_HOME="$workspace_home/.codex" \
      CODEX_INSTALL_DIR="$codex_install_dir" \
      CODEX_NON_INTERACTIVE=1 \
      CODEX_RELEASE=latest \
      PATH="$PATH:$codex_install_dir" \
      sh "$installer"
  fi
  status=$?
  rm -f "$installer"

  if ((status != 0)); then
    return "$status"
  fi

  touch "$success_stamp"

  # Retire the historical npm shim only after a standalone Codex install
  # succeeds, so an existing workspace never loses its last usable binary.
  legacy="$workspace_home/.local/bin/codex"
  if [[ -e "$legacy" || -L "$legacy" ]]; then
    backup="$state_dir/legacy-codex-$(date +%Y%m%d%H%M%S)"
    mv "$legacy" "$backup"
    warn "moved the previous user Codex command to $backup"
    warn 'run hash -r or open a new terminal before starting Codex'
  fi
}

update_codex() {
  local mode=$1
  local result

  if [[ $mode == auto ]]; then
    case ${CODEX_AUTO_UPDATE:-true} in
      0 | false | FALSE | no | NO)
        [[ -x "$codex_real" ]]
        return
        ;;
    esac

    if [[ -x "$codex_real" ]] && is_recent "$success_stamp" "$codex_update_interval"; then
      return 0
    fi
    if [[ -x "$codex_real" ]] && is_recent "$attempt_stamp" "$codex_failure_backoff"; then
      return 0
    fi
  fi

  mkdir -p "$state_dir"
  exec 9>"$update_lock"
  if ! flock -w 300 9; then
    warn 'timed out waiting for another Codex update'
    [[ -x "$codex_real" ]]
    return
  fi

  if [[ $mode == auto && -x "$codex_real" ]] && is_recent "$success_stamp" "$codex_update_interval"; then
    return 0
  fi

  touch "$attempt_stamp"
  printf 'Checking for a Codex update...\n' >&2
  if install_codex; then
    return 0
  else
    result=$?
  fi

  if [[ -x "$codex_real" ]]; then
    warn 'Codex update failed; continuing with the installed version'
    return 0
  fi

  warn 'Codex is not installed and the automatic installation failed'
  return "$result"
}

if [[ ${1:-} == update ]]; then
  update_codex force || exit
  "$codex_real" --version
  exit
fi

if ! update_codex auto && [[ ! -x "$codex_real" ]]; then
  printf 'error: Codex could not be installed automatically\n' >&2
  printf 'retry with: codex update\n' >&2
  exit 1
fi

if [[ ! -x "$codex_real" ]]; then
  printf 'error: Codex is not installed at %s\n' "$codex_real" >&2
  printf 'install it with: codex update\n' >&2
  exit 1
fi

export CODEX_HOME=${CODEX_HOME:-$workspace_home/.codex}
export CODEX_INSTALL_DIR="$codex_install_dir"
exec "$codex_real" "$@"
