#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/scripts/changelog-branch-update.sh"

test -f "$helper"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

new_fixture() {
  local name=$1
  local remote="$test_root/$name.git"
  local seed="$test_root/$name-seed"
  local worker="$test_root/$name-worker"

  git init -q --bare "$remote"
  git init -q -b main "$seed"
  git -C "$seed" config user.name "Fixture Author"
  git -C "$seed" config user.email "fixture@example.com"
  printf 'base\n' > "$seed/history.txt"
  git -C "$seed" add history.txt
  git -C "$seed" commit -q -m 'feat: base'
  git -C "$seed" checkout -q -b feature
  git -C "$seed" remote add origin "$remote"
  git -C "$seed" push -q origin main feature

  git clone -q --branch feature "$remote" "$worker"
  git -C "$worker" config user.name "github-actions[bot]"
  git -C "$worker" config user.email "41898282+github-actions[bot]@users.noreply.github.com"

  printf '%s\n' "$remote|$seed|$worker"
}

make_changelog_commit() {
  local worker=$1
  printf '# Changelog\n' > "$worker/CHANGELOG.md"
  git -C "$worker" add CHANGELOG.md
  git -C "$worker" commit -q -m 'docs(changelog): update'
}

# Current head: the changelog commit must fast-forward the branch.
IFS='|' read -r remote seed worker < <(new_fixture current)
expected=$(git -C "$worker" rev-parse HEAD)
make_changelog_commit "$worker"
local_commit=$(git -C "$worker" rev-parse HEAD)
(
  cd "$worker"
  bash "$helper" push "$expected" feature
)
test "$(git --git-dir="$remote" rev-parse refs/heads/feature)" = "$local_commit"

# Stale head: another commit wins. The stale changelog run exits successfully
# and must not move the remote branch.
IFS='|' read -r remote seed worker < <(new_fixture stale)
expected=$(git -C "$worker" rev-parse HEAD)
make_changelog_commit "$worker"
printf 'new head\n' >> "$seed/history.txt"
git -C "$seed" add history.txt
git -C "$seed" commit -q -m 'fix: advance feature'
git -C "$seed" push -q origin feature
winning_head=$(git -C "$seed" rev-parse HEAD)
status=$(
  cd "$worker"
  bash "$helper" status "$expected" feature
)
test "$status" = stale
(
  cd "$worker"
  bash "$helper" push "$expected" feature
)
test "$(git --git-dir="$remote" rev-parse refs/heads/feature)" = "$winning_head"

# Real push failure: if the remote still points at the expected event head,
# rejection is not a stale race and must remain fatal.
IFS='|' read -r remote seed worker < <(new_fixture rejected)
expected=$(git -C "$worker" rev-parse HEAD)
make_changelog_commit "$worker"
cat > "$remote/hooks/pre-receive" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$remote/hooks/pre-receive"
if (
  cd "$worker"
  bash "$helper" push "$expected" feature
); then
  echo 'real push rejection was incorrectly treated as success' >&2
  exit 1
fi
test "$(git --git-dir="$remote" rev-parse refs/heads/feature)" = "$expected"

echo 'changelog race tests passed'
