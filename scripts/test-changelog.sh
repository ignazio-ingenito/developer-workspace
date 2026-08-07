#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workflow="$repo_root/.github/workflows/changelog-reusable.yml"
wrapper="$repo_root/.github/workflows/changelog.yml"
git_cliff=${GIT_CLIFF:-git-cliff}

test -f "$workflow"
test -f "$wrapper"
command -v "$git_cliff" >/dev/null

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

config="$test_root/cliff.toml"
awk '
  /# BEGIN COMMON CLIFF CONFIG/ { copying = 1; next }
  /# END COMMON CLIFF CONFIG/ { copying = 0; exit }
  copying { sub(/^          /, ""); print }
' "$workflow" > "$config"
test -s "$config"

fixture="$test_root/repository"
git init -q -b main "$fixture"
git -C "$fixture" config user.name "Fixture Author"
git -C "$fixture" config user.email "fixture@example.com"

commit() {
  local message=$1
  local marker=$2
  printf '%s\n' "$marker" >> "$fixture/history.txt"
  git -C "$fixture" add history.txt
  git -C "$fixture" commit -q -m "$message"
}

commit "feat: tagged feature" "tagged"
git -C "$fixture" tag v1.0.0
commit "feat: add feature" "feature"
commit "fix: correct bug" "bugfix"
commit "perf: reduce latency" "performance"
commit "refactor: simplify flow" "refactoring"
commit "docs: explain usage" "documentation"
commit "test: cover behavior" "tests"
commit "ci: validate workflow" "ci"
commit "chore: maintain tooling" "maintenance"
commit "revert: undo regression" "revert"
commit "describe an unconventional change" "unconventional"

git -C "$fixture" -c user.name=github-actions -c user.email=41898282+github-actions\[bot\]@users.noreply.github.com \
  commit --allow-empty -q -m "docs(changelog): update"

(
  cd "$fixture"
  "$git_cliff" --config "$config" --output CHANGELOG.md
)

changelog="$fixture/CHANGELOG.md"
test -f "$changelog"
grep -Fxq "## Unreleased" "$changelog"
grep -Eq '^## \[?v?1\.0\.0\]?' "$changelog"

for group in \
  "Features" \
  "Bug fixes" \
  "Performance" \
  "Refactoring" \
  "Documentation" \
  "Tests" \
  "CI" \
  "Maintenance" \
  "Reverts"; do
  grep -Fq "### $group" "$changelog"
done

grep -Fq "Add feature" "$changelog"
grep -Fq "Describe an unconventional change" "$changelog"
if grep -Fq "docs(changelog): update" "$changelog"; then
  echo "bot changelog commit leaked into CHANGELOG.md" >&2
  exit 1
fi

before=$(sha256sum "$changelog")
(
  cd "$fixture"
  "$git_cliff" --config "$config" --output CHANGELOG.md
)
after=$(sha256sum "$changelog")
test "$before" = "$after"

untagged="$test_root/untagged"
git init -q -b master "$untagged"
git -C "$untagged" config user.name "Fixture Author"
git -C "$untagged" config user.email "fixture@example.com"
printf '%s\n' "first" > "$untagged/history.txt"
git -C "$untagged" add history.txt
git -C "$untagged" commit -q -m "feat: first untagged feature"
(
  cd "$untagged"
  "$git_cliff" --config "$config" --output CHANGELOG.md
)
grep -Fxq "## Unreleased" "$untagged/CHANGELOG.md"
grep -Fq "First untagged feature" "$untagged/CHANGELOG.md"

grep -Fq 'on:' "$workflow"
grep -Fq 'workflow_call:' "$workflow"
grep -Fq 'github.event.pull_request.head.repo.full_name == github.repository' "$workflow"
grep -Fq 'github.event.pull_request.head.ref != github.event.repository.default_branch' "$workflow"
grep -Fq "github.actor != 'ignazio-changelog[bot]'" "$workflow"
grep -Fq 'fetch-depth: 0' "$workflow"
grep -Fq 'permission-contents: write' "$workflow"
grep -Fq 'actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1' "$workflow"
grep -Fq 'actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09' "$workflow"
grep -Fq 'orhun/git-cliff-action@f50e11560dce63f7c33227798f90b924471a88b5' "$workflow"
grep -Fq 'args: --no-exec --verbose' "$workflow"
grep -Fq 'git add -- CHANGELOG.md' "$workflow"
grep -Fq 'HEAD_REF: ${{ github.event.pull_request.head.ref }}' "$workflow"
grep -Fq 'git push origin "HEAD:$HEAD_REF"' "$workflow"
grep -Fq 'docs(changelog): update' "$workflow"
grep -Fq 'uses: ./.github/workflows/changelog-reusable.yml' "$wrapper"

if grep -Eq 'pull_request_target|git add \.|git push .*--force|\[skip ci\]' "$workflow" "$wrapper"; then
  echo "unsafe changelog workflow pattern found" >&2
  exit 1
fi

echo "changelog tests passed"
