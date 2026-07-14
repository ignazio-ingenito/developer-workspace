#!/usr/bin/env bash
set -uo pipefail

home=${HOME:-/home/coder}
mise_command=${MISE_COMMAND:-/usr/local/bin/mise}
mise_config=${MISE_GLOBAL_CONFIG_FILE:-/opt/developer-workspace/mise-workspace-tools.toml}
mise_user_binary=${MISE_USER_BINARY:-$home/.local/bin/mise}
codex_install_dir=${CODEX_INSTALL_DIR:-$home/.local/libexec/codex}
codex_real="$codex_install_dir/codex"
codex_installer_url=${CODEX_INSTALLER_URL:-https://chatgpt.com/codex/install.sh}
codex_update_interval=${CODEX_AUTO_UPDATE_INTERVAL:-21600}
codex_failure_backoff=${CODEX_AUTO_UPDATE_FAILURE_BACKOFF:-900}
codex_update_timeout=${CODEX_AUTO_UPDATE_TIMEOUT:-120}
state_dir="$home/.cache/developer-workspace"
mise_bootstrap_stamp="$state_dir/mise-bootstrap"
codex_success_stamp="$state_dir/codex-update-success"
codex_attempt_stamp="$state_dir/codex-update-attempt"
codex_lock="$state_dir/codex-update.lock"

home_tools=(
  mise node npm npx python3 uv gh chezmoi bw sops age kubectl helm kustomize tofu
  ansible jq yq rg fd shellcheck
)
image_tools=(
  code-server git tmux curl gpg less make sudo unzip wget ssh bash
)
tools=(codex "${home_tools[@]}" "${image_tools[@]}")

usage() {
  cat <<'EOF'
Usage:
  workspace-tools                 Show versions, ownership, and active paths
  workspace-tools status          Show versions, ownership, and active paths
  workspace-tools update          Update mise, all mise-managed tools, and Codex
  workspace-tools update codex    Update only Codex
  workspace-tools bootstrap       Install missing workspace tools in the home

Project-specific versions remain owned by each repository through mise.toml.
Operating-system bootstrap tools require an image rebuild.
EOF
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

first_line() {
  local output
  output=$("$@" 2>&1 || true)
  printf '%s\n' "$output" | sed -n '1p'
}

stdout_first_line() {
  local output
  output=$("$@" 2>/dev/null || true)
  printf '%s\n' "$output" | sed -n '1p'
}

version_field() {
  local field=$1
  shift
  local output
  output=$("$@" 2>/dev/null || true)
  printf '%s\n' "$output" | sed -n "s/^${field}: //p" | sed -n '1p'
}

in_list() {
  local candidate=$1 item
  shift
  for item in "$@"; do
    [[ $candidate == "$item" ]] && return 0
  done
  return 1
}

mise_in_home() {
  (
    cd "$home" 2>/dev/null || exit 1
    "$mise_command" "$@"
  )
}

activate_mise_tools() {
  local bin_path
  while IFS= read -r bin_path; do
    [[ -n $bin_path ]] && PATH="$bin_path:$PATH"
  done < <(mise_in_home bin-paths 2>/dev/null || true)
  export PATH
}

mise_config_signature() {
  [[ -f $mise_config ]] || return 1
  cksum "$mise_config" | awk '{print $1 ":" $2}'
}

mark_mise_bootstrap() {
  local signature
  signature=$(mise_config_signature) || return 0
  mkdir -p "$state_dir"
  printf '%s\n' "$signature" >"$mise_bootstrap_stamp"
}

mise_bootstrap_is_current() {
  local expected actual
  [[ -f $mise_bootstrap_stamp ]] || return 1
  expected=$(mise_config_signature) || return 1
  actual=$(sed -n '1p' "$mise_bootstrap_stamp" 2>/dev/null)
  [[ $actual == "$expected" ]]
}

bootstrap_mise_tools() {
  local mode=${1:-cached}

  if [[ $mode == cached ]] && mise_bootstrap_is_current; then
    activate_mise_tools
    return 0
  fi

  if ! "$mise_command" --version >/dev/null 2>&1; then
    warn 'mise could not be initialized in the persistent home'
    return 1
  fi

  printf 'Installing workspace tools in the persistent home...\n' >&2
  mise_in_home install node python uv || return
  activate_mise_tools
  mise_in_home install || return
  activate_mise_tools
  mark_mise_bootstrap
}

update_mise_tools() {
  if ! "$mise_command" --version >/dev/null 2>&1; then
    warn 'mise could not be initialized in the persistent home'
    return 1
  fi

  printf 'Updating mise in the persistent home...\n' >&2
  if ! "$mise_command" -y self-update; then
    warn 'mise self-update failed; continuing with the installed version'
  fi

  bootstrap_mise_tools force || return
  printf 'Updating mise-managed workspace tools...\n' >&2
  mise_in_home -y upgrade || return
  activate_mise_tools
  mark_mise_bootstrap
}

tool_path() {
  local tool=$1

  case "$tool" in
    codex)
      [[ -x $codex_real ]] && printf '%s\n' "$codex_real" || printf '%s\n' '-'
      ;;
    mise)
      [[ -x $mise_user_binary ]] && printf '%s\n' "$mise_user_binary" || printf '%s\n' '-'
      ;;
    *) command -v "$tool" 2>/dev/null || printf '%s\n' '-' ;;
  esac
}

tool_version() {
  local tool=$1

  if [[ $tool == codex ]]; then
    [[ -x $codex_real ]] && first_line "$codex_real" --version || printf '%s\n' 'not installed'
    return
  fi

  if [[ $tool == mise ]]; then
    [[ -x $mise_user_binary ]] && first_line "$mise_user_binary" --version || printf '%s\n' 'not installed'
    return
  fi

  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '%s\n' 'missing'
    return
  fi

  case "$tool" in
    code-server) first_line code-server --version ;;
    node) first_line node --version ;;
    npm | npx | bw) stdout_first_line "$tool" --version ;;
    python3) first_line python3 --version ;;
    uv) first_line uv --version ;;
    git) first_line git --version ;;
    gh) first_line gh --version ;;
    tmux) first_line tmux -V ;;
    chezmoi) first_line chezmoi --version ;;
    sops) first_line sops --version ;;
    age) first_line age --version ;;
    kubectl) first_line kubectl version --client=true ;;
    helm) first_line helm version --short ;;
    kustomize) first_line kustomize version ;;
    tofu) first_line tofu version ;;
    ansible) first_line ansible --version ;;
    jq) first_line jq --version ;;
    yq) first_line yq --version ;;
    rg) first_line rg --version ;;
    fd) first_line fd --version ;;
    curl) first_line curl --version ;;
    gpg) first_line gpg --version ;;
    less) first_line less --version ;;
    make) first_line make --version ;;
    shellcheck) version_field version shellcheck --version ;;
    sudo) stdout_first_line dpkg-query -W "-f=\${Version}\n" sudo ;;
    unzip) first_line unzip -v ;;
    wget) first_line wget --version ;;
    ssh) first_line ssh -V ;;
    bash) first_line bash --version ;;
    *) printf '%s\n' 'unknown' ;;
  esac
}

tool_owner() {
  local tool=$1
  if [[ $tool == codex ]] || in_list "$tool" "${home_tools[@]}"; then
    printf '%s\n' 'home'
  else
    printf '%s\n' 'image'
  fi
}

tool_update_method() {
  local tool=$1
  if [[ $tool == codex ]]; then
    printf '%s\n' 'automatic'
  elif in_list "$tool" "${home_tools[@]}"; then
    printf '%s\n' 'mise'
  else
    printf '%s\n' 'rebuild'
  fi
}

show_status() {
  local tool version owner method path

  "$mise_command" --version >/dev/null 2>&1 || true
  activate_mise_tools

  printf '%-13s %-7s %-11s %-30s %s\n' \
    'TOOL' 'OWNER' 'UPDATE' 'VERSION' 'ACTIVE PATH'
  printf '%-13s %-7s %-11s %-30s %s\n' \
    '-------------' '-------' '-----------' '------------------------------' '-----------'

  for tool in "${tools[@]}"; do
    version=$(tool_version "$tool")
    owner=$(tool_owner "$tool")
    method=$(tool_update_method "$tool")
    path=$(tool_path "$tool")
    printf '%-13s %-7s %-11s %-30s %s\n' \
      "$tool" "$owner" "$method" "$version" "$path"
  done

  printf '\nHome tools persist across Pod recreation and update with workspace-tools update.\n'
  printf 'Image bootstrap tools require an image rebuild and rollout.\n'
  printf 'Repository mise.toml files still control project-specific versions.\n'
}

file_is_younger_than() {
  local file=$1
  local max_age=$2
  local now modified

  [[ -e $file ]] || return 1
  [[ $max_age =~ ^[0-9]+$ ]] || return 1
  now=$(date +%s)
  modified=$(stat -c %Y "$file" 2>/dev/null || printf '0')
  ((now - modified < max_age))
}

run_codex_installer() {
  local installer result
  installer=$(mktemp)

  if [[ ! $codex_update_timeout =~ ^[1-9][0-9]*$ ]]; then
    codex_update_timeout=120
  fi

  if ! curl -fsSL --connect-timeout 10 --max-time 60 \
    "$codex_installer_url" -o "$installer"; then
    rm -f "$installer"
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout "$codex_update_timeout" env \
      CODEX_HOME="$home/.codex" \
      CODEX_INSTALL_DIR="$codex_install_dir" \
      CODEX_NON_INTERACTIVE=1 \
      CODEX_RELEASE=latest \
      PATH="$PATH:$codex_install_dir" \
      sh "$installer"
  else
    env \
      CODEX_HOME="$home/.codex" \
      CODEX_INSTALL_DIR="$codex_install_dir" \
      CODEX_NON_INTERACTIVE=1 \
      CODEX_RELEASE=latest \
      PATH="$PATH:$codex_install_dir" \
      sh "$installer"
  fi
  result=$?
  rm -f "$installer"
  return "$result"
}

retire_legacy_user_codex() {
  local legacy_bin="$home/.local/bin/codex"
  local backup

  [[ -e $legacy_bin || -L $legacy_bin ]] || return 0

  if command -v npm >/dev/null 2>&1; then
    npm uninstall --global --prefix "$home/.local" @openai/codex \
      >/dev/null 2>&1 || true
  fi

  if [[ -e $legacy_bin || -L $legacy_bin ]]; then
    backup="$state_dir/legacy-codex-$(date +%Y%m%d%H%M%S)"
    mv "$legacy_bin" "$backup"
    warn "moved the previous user Codex command to $backup"
    warn 'run hash -r or open a new terminal before starting Codex'
  fi
}

update_codex() {
  local mode=${1:-force}
  local result

  mkdir -p "$state_dir" "$codex_install_dir"

  if [[ $mode == auto && -x $codex_real ]] && \
    file_is_younger_than "$codex_success_stamp" "$codex_update_interval"; then
    return 0
  fi

  if [[ $mode == auto && -x $codex_real ]] && \
    file_is_younger_than "$codex_attempt_stamp" "$codex_failure_backoff"; then
    return 0
  fi

  exec 9>"$codex_lock"
  if ! flock -w 300 9; then
    warn 'timed out waiting for another Codex update'
    [[ -x $codex_real ]]
    return
  fi

  if [[ $mode == auto && -x $codex_real ]] && \
    file_is_younger_than "$codex_success_stamp" "$codex_update_interval"; then
    return 0
  fi

  touch "$codex_attempt_stamp"
  printf 'Checking for a Codex update...\n' >&2
  if run_codex_installer; then
    touch "$codex_success_stamp"
    if [[ $mode == force ]]; then
      retire_legacy_user_codex
    fi
    return 0
  else
    result=$?
  fi

  if [[ -x $codex_real ]]; then
    warn 'Codex update failed; continuing with the installed version'
    return 0
  fi

  warn 'Codex is not installed and the automatic installation failed'
  return "$result"
}

bootstrap_all() {
  local result=0

  bootstrap_mise_tools cached || result=$?
  if [[ ! -x $codex_real || -e $home/.local/bin/codex || -L $home/.local/bin/codex ]]; then
    update_codex force || result=$?
  fi
  return "$result"
}

update_all() {
  update_mise_tools || return
  update_codex force || return
  printf '\nWorkspace tools are up to date.\n\n'
  show_status
  printf '\nRun hash -r in shells that were already open.\n'
}

command_name=${1:-status}
case "$command_name" in
  status) show_status ;;
  bootstrap) bootstrap_all ;;
  update)
    case "${2:-all}" in
      all) update_all ;;
      codex) update_codex force ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  _auto-update-codex)
    case ${CODEX_AUTO_UPDATE:-true} in
      0 | false | FALSE | no | NO) exit 0 ;;
      *) update_codex auto ;;
    esac
    ;;
  help | --help | -h) usage ;;
  *) usage >&2; exit 2 ;;
esac
