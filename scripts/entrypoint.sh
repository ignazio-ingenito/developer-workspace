#!/usr/bin/env bash
set -euo pipefail

workspace_home=${HOME:-/home/coder}
workspaces_root=${WORKSPACES_ROOT:-/workspaces}
baseline_bashrc=${DEVELOPER_WORKSPACE_BASHRC:-/opt/developer-workspace/bashrc}
baseline_tmux=${DEVELOPER_WORKSPACE_TMUX_CONF:-/opt/developer-workspace/tmux.conf}
baseline_extensions=${DEVELOPER_WORKSPACE_BASELINE_EXTENSIONS:-/opt/developer-workspace/code-server-extensions}
mise_command=${MISE_COMMAND:-/usr/local/bin/mise}
bootstrap_timeout=${WORKSPACE_BOOTSTRAP_TIMEOUT:-300}
extensions_dir="$workspace_home/.local/share/code-server/extensions"

mkdir -p \
  "$workspace_home/.config/code-server" \
  "$extensions_dir" \
  "$workspace_home/.cache" \
  "$workspace_home/.cache/developer-workspace" \
  "$workspace_home/.cache/npm" \
  "$workspace_home/.local/bin" \
  "$workspace_home/.local/libexec/codex" \
  "$workspace_home/.ssh" \
  "$workspace_home/.config/Bitwarden CLI" \
  "$workspace_home/.config/sops/age" \
  "$workspaces_root"

chmod 700 "$workspace_home/.ssh" "$workspace_home/.config/sops/age"

# A PVC mounted on /home/coder hides image-layer files. Seed the immutable
# baseline without replacing user-installed or user-updated extensions.
if [[ -d "$baseline_extensions" ]]; then
  cp -a --no-clobber "$baseline_extensions/." "$extensions_dir/"
fi

# Seed only a brand-new home. Existing and chezmoi-managed files are never
# rewritten at container startup.
if [[ ! -e "$workspace_home/.bashrc" ]]; then
  install -m 0644 "$baseline_bashrc" "$workspace_home/.bashrc"
fi

if [[ ! -e "$workspace_home/.tmux.conf" ]]; then
  install -m 0644 "$baseline_tmux" "$workspace_home/.tmux.conf"
fi

run_with_timeout() {
  if [[ $bootstrap_timeout =~ ^[1-9][0-9]*$ ]] && command -v timeout >/dev/null 2>&1; then
    timeout "$bootstrap_timeout" "$@"
  else
    "$@"
  fi
}

# mise owns the home tool manifest and performs idempotent installs. Languages
# required by npm/pipx backends are installed first. A registry outage remains
# non-fatal so code-server can start with the already installed toolset.
case ${WORKSPACE_BOOTSTRAP:-true} in
  0 | false | FALSE | no | NO) ;;
  *)
    bootstrap_status=0
    (
      cd "$workspace_home"
      run_with_timeout "$mise_command" install node python uv
      run_with_timeout "$mise_command" install
      run_with_timeout "$mise_command" reshim -f
      run_with_timeout /usr/local/bin/codex --version >/dev/null
    ) || bootstrap_status=$?

    if ((bootstrap_status != 0)); then
      printf 'warning: workspace bootstrap failed; retry with mise install and codex update\n' >&2
    fi
    ;;
esac

exec "$@"
