#!/usr/bin/env bash
set -euo pipefail

home=${HOME:-/home/coder}
workspaces_root=${WORKSPACES_ROOT:-/workspaces}
baseline_bashrc=${DEVELOPER_WORKSPACE_BASHRC:-/opt/developer-workspace/bashrc}
baseline_tmux=${DEVELOPER_WORKSPACE_TMUX_CONF:-/opt/developer-workspace/tmux.conf}

mkdir -p \
  "$home/.config/code-server" \
  "$home/.local/share/code-server/extensions" \
  "$home/.cache" \
  "$home/.ssh" \
  "$home/.config/Bitwarden CLI" \
  "$home/.config/sops/age" \
  "$workspaces_root"

chmod 700 "$home/.ssh" "$home/.config/sops/age"

# Seed only a brand-new home. Existing and chezmoi-managed files are never
# rewritten at container startup.
if [[ ! -e "$home/.bashrc" ]]; then
  install -m 0644 "$baseline_bashrc" "$home/.bashrc"
fi

if [[ ! -e "$home/.tmux.conf" ]]; then
  install -m 0644 "$baseline_tmux" "$home/.tmux.conf"
fi

exec "$@"
