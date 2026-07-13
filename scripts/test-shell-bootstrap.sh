#!/usr/bin/env bash
set -euo pipefail

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

home="$tmp_dir/home"
workspaces="$tmp_dir/workspaces"
baseline_extensions="$tmp_dir/baseline-extensions"
mkdir -p "$home" "$baseline_extensions/redhat.vscode-yaml-test"
printf '%s\n' baseline > "$baseline_extensions/redhat.vscode-yaml-test/source"

HOME="$home" \
WORKSPACES_ROOT="$workspaces" \
DEVELOPER_WORKSPACE_BASELINE_EXTENSIONS="$baseline_extensions" \
/usr/local/lib/developer-workspace/entrypoint.sh true

test -f "$home/.bashrc"
test -f "$home/.tmux.conf"
test "$(stat -c '%a' "$home/.ssh")" = 700
test "$(stat -c '%a' "$home/.config/sops/age")" = 700
test -d "$home/.local/share/code-server/extensions"
grep -Fxq baseline "$home/.local/share/code-server/extensions/redhat.vscode-yaml-test/source"

if grep -Eq 'plugins=\([^)]*([[:space:]]|^)mise([[:space:]]|\))' "$home/.bashrc"; then
  echo "baseline requests unavailable Oh My Bash mise plugin" >&2
  exit 1
fi

if grep -Eq 'aliases=\([^)]*([[:space:]]|^)git([[:space:]]|\))' "$home/.bashrc"; then
  echo "baseline requests unavailable Oh My Bash git alias module" >&2
  exit 1
fi

set +e
shell_output=$(HOME="$home" bash --noprofile --norc -i -c 'exit' 2>&1)
shell_status=$?
set -e
if ((shell_status != 0)); then
  printf '%s\n' "$shell_output" >&2
  echo "interactive shell startup failed with status $shell_status" >&2
  exit 1
fi
if grep -Fq 'module_require' <<<"$shell_output"; then
  printf '%s\n' "$shell_output" >&2
  exit 1
fi

printf '%s\n' '# user-owned' > "$home/.bashrc"
printf '%s\n' user-owned > "$home/.local/share/code-server/extensions/redhat.vscode-yaml-test/source"
HOME="$home" \
WORKSPACES_ROOT="$workspaces" \
DEVELOPER_WORKSPACE_BASELINE_EXTENSIONS="$baseline_extensions" \
/usr/local/lib/developer-workspace/entrypoint.sh true
grep -Fxq '# user-owned' "$home/.bashrc"
grep -Fxq user-owned "$home/.local/share/code-server/extensions/redhat.vscode-yaml-test/source"

echo "shell bootstrap test passed"
