#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  /home/coder/.config/code-server \
  /home/coder/.local/share/code-server/extensions \
  /home/coder/.cache \
  /home/coder/.ssh \
  "/home/coder/.config/Bitwarden CLI" \
  /workspaces

chmod 700 /home/coder/.ssh

if [[ ! -d /home/coder/.oh-my-bash ]]; then
  cp -a /opt/oh-my-bash /home/coder/.oh-my-bash
fi

if [[ ! -f /home/coder/.bashrc ]]; then
  cat > /home/coder/.bashrc <<'BASHRC'
export OSH="$HOME/.oh-my-bash"
OSH_THEME="font"
completions=(git)
aliases=(general git)
plugins=(git mise)
source "$OSH/oh-my-bash.sh"
eval "$(mise activate bash)"
BASHRC
fi

exec "$@"
