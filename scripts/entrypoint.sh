#!/usr/bin/env bash
set -euo pipefail

home=${HOME:-/home/coder}
workspaces_root=${WORKSPACES_ROOT:-/workspaces}
baseline_bashrc=${DEVELOPER_WORKSPACE_BASHRC:-/opt/developer-workspace/bashrc}
baseline_tmux=${DEVELOPER_WORKSPACE_TMUX_CONF:-/opt/developer-workspace/tmux.conf}
baseline_extensions=${DEVELOPER_WORKSPACE_BASELINE_EXTENSIONS:-/opt/developer-workspace/code-server-extensions}
extensions_dir="$home/.local/share/code-server/extensions"

mkdir -p \
  "$home/.config/code-server" \
  "$extensions_dir" \
  "$home/.cache" \
  "$home/.cache/developer-workspace" \
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

exec "$@"
