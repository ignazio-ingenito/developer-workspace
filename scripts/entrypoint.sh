#!/usr/bin/env bash
set -euo pipefail

home=${HOME:-/home/coder}
workspaces_root=${WORKSPACES_ROOT:-/workspaces}
baseline_bashrc=${DEVELOPER_WORKSPACE_BASHRC:-/opt/developer-workspace/bashrc}
baseline_tmux=${DEVELOPER_WORKSPACE_TMUX_CONF:-/opt/developer-workspace/tmux.conf}
baseline_extensions=${DEVELOPER_WORKSPACE_BASELINE_EXTENSIONS:-/opt/developer-workspace/code-server-extensions}
workspace_tools=${WORKSPACE_TOOLS_COMMAND:-/usr/local/bin/workspace-tools}
bootstrap_timeout=${WORKSPACE_TOOLS_BOOTSTRAP_TIMEOUT:-300}
extensions_dir="$home/.local/share/code-server/extensions"

mkdir -p \
  "$home/.config/code-server" \
  "$extensions_dir" \
  "$home/.cache" \
  "$home/.cache/developer-workspace" \
  "$home/.cache/npm" \
  "$home/.local/bin" \
  "$home/.local/libexec/codex" \
  "$home/.ssh" \
  "$home/.config/Bitwarden CLI" \
  "$home/.config/sops/age" \
  "$workspaces_root"

chmod 700 "$home/.ssh" "$home/.config/sops/age"

# A PVC mounted on /home/coder hides image-layer files. Seed the immutable
# baseline without replacing user-installed or user-updated extensions.
if [[ -d "$baseline_extensions" ]]; then
  cp -a --no-clobber "$baseline_extensions/." "$extensions_dir/"
fi

# Seed only a brand-new home. Existing and chezmoi-managed files are never
# rewritten at container startup.
if [[ ! -e "$home/.bashrc" ]]; then
  install -m 0644 "$baseline_bashrc" "$home/.bashrc"
fi

if [[ ! -e "$home/.tmux.conf" ]]; then
  install -m 0644 "$baseline_tmux" "$home/.tmux.conf"
fi

# Install only missing or newly declared baseline tools. A transient registry
# outage must not prevent code-server from starting; the user can retry with
# `workspace-tools update` from a terminal.
case ${WORKSPACE_TOOLS_BOOTSTRAP:-true} in
  0 | false | FALSE | no | NO) ;;
  *)
    if [[ $bootstrap_timeout =~ ^[1-9][0-9]*$ ]] && command -v timeout >/dev/null 2>&1; then
      timeout "$bootstrap_timeout" "$workspace_tools" bootstrap || \
        printf 'warning: workspace tool bootstrap failed; run workspace-tools update\n' >&2
    else
      "$workspace_tools" bootstrap || \
        printf 'warning: workspace tool bootstrap failed; run workspace-tools update\n' >&2
    fi
    ;;
esac

exec "$@"
