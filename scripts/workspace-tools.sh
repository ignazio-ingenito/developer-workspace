#!/usr/bin/env bash
set -uo pipefail

home=${HOME:-/home/coder}
codex_install_dir=${CODEX_INSTALL_DIR:-$home/.local/libexec/codex}
codex_real="$codex_install_dir/codex"
codex_installer_url=${CODEX_INSTALLER_URL:-https://chatgpt.com/codex/install.sh}
codex_update_interval=${CODEX_AUTO_UPDATE_INTERVAL:-21600}
codex_failure_backoff=${CODEX_AUTO_UPDATE_FAILURE_BACKOFF:-900}
state_dir="$home/.cache/developer-workspace"
codex_success_stamp="$state_dir/codex-update-success"
codex_attempt_stamp="$state_dir/codex-update-attempt"
codex_lock="$state_dir/codex-update.lock"

tools=(
  codex code-server node npm npx git gh tmux mise chezmoi bw sops age kubectl
  helm kustomize tofu ansible jq yq rg fdfind curl gpg less make python3
  shellcheck sudo unzip wget ssh bash
)

usage() {
  cat <<'EOF'
Usage:
  workspace-tools                 Show installed workspace tool versions
  workspace-tools status          Show installed workspace tool versions
  workspace-tools update          Update runtime-managed tools
  workspace-tools update codex    Update Codex now

Image-owned tools are updated through Renovate, an image rebuild, and rollout.
Project toolchains remain owned by each repository through mise.
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

tool_path() {
  local tool=$1

  if [[ $tool == codex ]]; then
    if [[ -x $codex_real ]]; then
      printf '%s\n' "$codex_real"
    else
      printf '%s\n' '-'
    fi
    return
  fi

  command -v "$tool" 2>/dev/null || printf '%s\n' '-'
}

tool_version() {
  local tool=$1

  if [[ $tool != codex ]] && ! command -v "$tool" >/dev/null 2>&1; then
    printf '%s\n' 'missing'
    return
  fi

  case "$tool" in
    codex)
      if [[ -x $codex_real ]]; then
        first_line "$codex_real" --version
      else
        printf '%s\n' 'not installed'
      fi
      ;;
    code-server) first_line code-server --version ;;
    node) first_line node --version ;;
    npm) stdout_first_line npm --version ;;
    npx) stdout_first_line npx --version ;;
    git) first_line git --version ;;
    gh) first_line gh --version ;;
    tmux) first_line tmux -V ;;
    mise) first_line mise --version ;;
    chezmoi) first_line chezmoi --version ;;
    bw) first_line bw --version ;;
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
    fdfind) first_line fdfind --version ;;
    curl) first_line curl --version ;;
    gpg) first_line gpg --version ;;
    less) first_line less --version ;;
    make) first_line make --version ;;
    python3) first_line python3 --version ;;
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
  if [[ $1 == codex ]]; then
    printf '%s\n' 'home'
  else
    printf '%s\n' 'image'
  fi
}

tool_update_method() {
  if [[ $1 == codex ]]; then
    printf '%s\n' 'automatic'
  else
    printf '%s\n' 'rebuild'
  fi
}

show_status() {
  local tool version owner method path

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

  if command -v mise >/dev/null 2>&1; then
    local project_tools
    project_tools=$(mise current 2>/dev/null || true)
    if [[ -n $project_tools ]]; then
      printf '\nProject toolchains (mise):\n%s\n' "$project_tools"
    fi
  fi

  printf '\nImage-owned tools are updated by Renovate and/or a base-image refresh, then rebuilt and rolled out.\n'
  printf 'Codex is checked automatically before a new Codex session starts.\n'
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
  local installer
  installer=$(mktemp)

  if ! curl -fsSL --connect-timeout 10 --max-time 60 \
    "$codex_installer_url" -o "$installer"; then
    rm -f "$installer"
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout 300 env \
      CODEX_HOME="$home/.codex" \
      CODEX_INSTALL_DIR="$codex_install_dir" \
      CODEX_NON_INTERACTIVE=1 \
      CODEX_RELEASE=latest \
      PATH="/usr/local/bin:$codex_install_dir:$PATH" \
      sh "$installer"
  else
    env \
      CODEX_HOME="$home/.codex" \
      CODEX_INSTALL_DIR="$codex_install_dir" \
      CODEX_NON_INTERACTIVE=1 \
      CODEX_RELEASE=latest \
      PATH="/usr/local/bin:$codex_install_dir:$PATH" \
      sh "$installer"
  fi
  local result=$?
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

update_all() {
  update_codex force || return
  printf '\nRuntime-managed tools are up to date.\n'
  printf 'Image-owned tools require a Renovate PR, image rebuild, and rollout.\n\n'
  show_status
}

command_name=${1:-status}
case "$command_name" in
  status)
    show_status
    ;;
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
  help | --help | -h)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
