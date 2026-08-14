#!/usr/bin/env bash
set -euo pipefail

home=${HOME:-/home/coder}
seed=${MISE_BOOTSTRAP_BINARY:-/opt/mise-bootstrap}
user_mise=${MISE_USER_BINARY:-$home/.local/bin/mise}

if [[ ! -x $user_mise ]]; then
  if [[ ! -x $seed ]]; then
    printf 'error: mise bootstrap binary is missing: %s\n' "$seed" >&2
    exit 1
  fi
  mkdir -p "$(dirname -- "$user_mise")"
  install -m 0755 "$seed" "$user_mise"
fi

user_mise_dir=$(dirname -- "$user_mise")
export PATH="$user_mise_dir:$PATH"
exec "$user_mise" "$@"
