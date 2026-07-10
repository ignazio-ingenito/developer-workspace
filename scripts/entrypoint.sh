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

exec "$@"
