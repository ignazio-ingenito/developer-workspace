#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_root=$(mktemp -d)
test_home="$test_root/home"
install_dir="$test_home/.local/libexec/codex"
installer="$test_root/install.sh"
install_count="$test_root/install-count"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

mkdir -p "$test_home/.local/bin"
cat >"$installer" <<'EOF'
#!/bin/sh
set -eu

count=0
if [ -f "$TEST_INSTALL_COUNT" ]; then
  count=$(cat "$TEST_INSTALL_COUNT")
fi
count=$((count + 1))
printf '%s\n' "$count" >"$TEST_INSTALL_COUNT"

mkdir -p "$CODEX_INSTALL_DIR"
cat >"$CODEX_INSTALL_DIR/codex" <<'INNER'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  printf 'codex-cli 9.9.9\n'
  exit 0
fi
printf 'fake codex: %s\n' "$*"
INNER
chmod 0755 "$CODEX_INSTALL_DIR/codex"
EOF

cat >"$test_home/.local/bin/codex" <<'EOF'
#!/bin/sh
printf 'legacy codex\n'
EOF
chmod 0755 "$test_home/.local/bin/codex"

common_env=(
  HOME="$test_home"
  CODEX_INSTALL_DIR="$install_dir"
  CODEX_INSTALLER_URL="file://$installer"
  TEST_INSTALL_COUNT="$install_count"
)

env "${common_env[@]}" "$script_dir/workspace-tools.sh" update codex
test -x "$install_dir/codex"
test ! -e "$test_home/.local/bin/codex"
test "$(cat "$install_count")" = 1

env "${common_env[@]}" "$script_dir/workspace-tools.sh" _auto-update-codex
test "$(cat "$install_count")" = 1

version=$(
  env "${common_env[@]}" \
    CODEX_AUTO_UPDATE=false \
    WORKSPACE_TOOLS_COMMAND="$script_dir/workspace-tools.sh" \
    "$script_dir/codex-launcher.sh" --version
)
test "$version" = 'codex-cli 9.9.9'

rm -f \
  "$test_home/.cache/developer-workspace/codex-update-success" \
  "$test_home/.cache/developer-workspace/codex-update-attempt"
version=$(
  env "${common_env[@]}" \
    CODEX_AUTO_UPDATE_FAILURE_BACKOFF=0 \
    CODEX_INSTALLER_URL="file://$test_root/does-not-exist" \
    WORKSPACE_TOOLS_COMMAND="$script_dir/workspace-tools.sh" \
    "$script_dir/codex-launcher.sh" --version
)
test "$version" = 'codex-cli 9.9.9'

env "${common_env[@]}" "$script_dir/workspace-tools.sh" status \
  | grep -F 'codex-cli 9.9.9' >/dev/null

if env \
  HOME="$test_root/missing-home" \
  CODEX_INSTALL_DIR="$test_root/missing-home/libexec/codex" \
  CODEX_INSTALLER_URL="file://$test_root/does-not-exist" \
  "$script_dir/workspace-tools.sh" update codex; then
  printf 'expected a missing first-time installer to fail\n' >&2
  exit 1
fi

printf 'workspace tools test passed\n'
