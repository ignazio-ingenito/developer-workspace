#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_root=$(mktemp -d)
test_home="$test_root/home"
install_dir="$test_home/.local/libexec/codex"
installer="$test_root/install.sh"
install_count="$test_root/install-count"
mise_log="$test_root/mise.log"
mise_config="$test_root/workspace-tools.toml"
fake_mise="$test_root/mise"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

mkdir -p "$test_home/.local/bin"
cat >"$mise_config" <<'EOF'
[tools]
node = "lts"
python = "3.13"
uv = "latest"
EOF

cat >"$fake_mise" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$TEST_MISE_LOG"
case "$*" in
  --version) printf 'mise 99.0.0\n' ;;
  bin-paths) : ;;
  *) : ;;
esac
EOF
chmod 0755 "$fake_mise"

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
  MISE_COMMAND="$fake_mise"
  MISE_GLOBAL_CONFIG_FILE="$mise_config"
  CODEX_INSTALL_DIR="$install_dir"
  CODEX_INSTALLER_URL="file://$installer"
  TEST_INSTALL_COUNT="$install_count"
  TEST_MISE_LOG="$mise_log"
)

env "${common_env[@]}" "$script_dir/workspace-tools.sh" bootstrap
first_install_lines=$(grep -c '^install' "$mise_log")
test "$(cat "$install_count")" = 1
env "${common_env[@]}" "$script_dir/workspace-tools.sh" bootstrap
test "$(grep -c '^install' "$mise_log")" = "$first_install_lines"
test "$(cat "$install_count")" = 1

# A persisted home must re-bootstrap when the baseline mise manifest changes,
# then cache the new signature so subsequent starts stay fast.
cat >>"$mise_config" <<'EOF'
"aqua:argoproj/argo-cd" = "latest"
EOF
env "${common_env[@]}" "$script_dir/workspace-tools.sh" bootstrap
changed_install_lines=$(grep -c '^install' "$mise_log")
test "$changed_install_lines" -gt "$first_install_lines"
env "${common_env[@]}" "$script_dir/workspace-tools.sh" bootstrap
test "$(grep -c '^install' "$mise_log")" = "$changed_install_lines"

env "${common_env[@]}" "$script_dir/workspace-tools.sh" update
test -x "$install_dir/codex"
test ! -e "$test_home/.local/bin/codex"
test "$(cat "$install_count")" = 2
grep -Fxq -- '-y self-update' "$mise_log"
grep -Fxq -- '-y upgrade' "$mise_log"

env "${common_env[@]}" "$script_dir/workspace-tools.sh" _auto-update-codex
test "$(cat "$install_count")" = 2

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

launcher_home="$test_root/launcher-home"
HOME="$launcher_home" \
MISE_BOOTSTRAP_BINARY="$fake_mise" \
MISE_USER_BINARY="$launcher_home/.local/bin/mise" \
TEST_MISE_LOG="$mise_log" \
  "$script_dir/mise-launcher.sh" --version | grep -Fxq 'mise 99.0.0'
test -x "$launcher_home/.local/bin/mise"

if env \
  HOME="$test_root/missing-home" \
  MISE_COMMAND="$fake_mise" \
  MISE_GLOBAL_CONFIG_FILE="$mise_config" \
  TEST_MISE_LOG="$mise_log" \
  CODEX_INSTALL_DIR="$test_root/missing-home/libexec/codex" \
  CODEX_INSTALLER_URL="file://$test_root/does-not-exist" \
  "$script_dir/workspace-tools.sh" update codex; then
  printf 'expected a missing first-time installer to fail\n' >&2
  exit 1
fi

printf 'workspace tools test passed\n'
