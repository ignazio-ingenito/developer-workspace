#!/usr/bin/env bash
set -euo pipefail

session=${1:-work}

if [[ ! "$session" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid tmux session name: $session" >&2
  exit 2
fi

exec tmux new-session -A -s "$session"
