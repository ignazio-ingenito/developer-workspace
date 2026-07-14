#!/usr/bin/env bash
set -uo pipefail

home=${HOME:-/home/coder}
codex_install_dir=${CODEX_INSTALL_DIR:-$home/.local/libexec/codex}
codex_real="$codex_install_dir/codex"
workspace_tools=${WORKSPACE_TOOLS_COMMAND:-/usr/local/bin/workspace-tools}

if [[ ${1:-} == update ]]; then
  exec "$workspace_tools" update codex
fi

if ! "$workspace_tools" _auto-update-codex; then
  if [[ ! -x $codex_real ]]; then
    printf 'error: Codex could not be installed automatically\n' >&2
    printf 'retry with: workspace-tools update codex\n' >&2
    exit 1
  fi
fi

if [[ ! -x $codex_real ]]; then
  printf 'error: Codex is not installed at %s\n' "$codex_real" >&2
  printf 'install it with: workspace-tools update codex\n' >&2
  exit 1
fi

export CODEX_HOME=${CODEX_HOME:-$home/.codex}
export CODEX_INSTALL_DIR=$codex_install_dir
exec "$codex_real" "$@"
