#!/usr/bin/env bash
set -euo pipefail

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

home="$tmp_dir/home"
workspaces="$tmp_dir/workspaces"
mkdir -p "$home"

HOME="$home" \
WORKSPACES_ROOT="$workspaces" \
/usr/local/lib/developer-workspace/entrypoint.sh true

test -f "$home/.bashrc"
test -f "$home/.tmux.conf"
test "$(stat -c '%a' "$home/.ssh")" = 700
test "$(stat -c '%a' "$home/.config/sops/age")" = 700
test -d "$home/.local/share/code-server/extensions"

if grep -Eq 'plugins=\([^)]*([[:space:]]|^)mise([[:space:]]|\))' "$home/.bashrc"; then
  echo "baseline requests unavailable Oh My Bash mise plugin" >&2
  exit 1
fi

if grep -Eq 'aliases=\([^)]*([[:space:]]|^)git([[:space:]]|\))' "$home/.bashrc"; then
  echo "baseline requests unavailable Oh My Bash git alias module" >&2
  exit 1
fi

shell_output=$(HOME="$home" bash --noprofile --norc -i -c 'exit' 2>&1 || true)
if grep -Fq 'module_require' <<<"$shell_output"; then
  printf '%s\n' "$shell_output" >&2
  exit 1
fi

printf '%s\n' '# user-owned' > "$home/.bashrc"
HOME="$home" \
WORKSPACES_ROOT="$workspaces" \
/usr/local/lib/developer-workspace/entrypoint.sh true
grep -Fxq '# user-owned' "$home/.bashrc"

echo "shell bootstrap test passed"
