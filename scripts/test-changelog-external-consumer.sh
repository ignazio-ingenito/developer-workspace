#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workflow="$repo_root/.github/workflows/changelog-reusable.yml"

test -f "$workflow"

# A called workflow executes in the caller repository context. Its support
# files must therefore be loaded from the exact called-workflow revision, not
# assumed to exist in the caller checkout.
grep -qF "repository: \${{ job.workflow_repository }}" "$workflow"
grep -qF "ref: \${{ job.workflow_sha }}" "$workflow"
grep -qF "bash \"\$RUNNER_TEMP/changelog-branch-update.sh\" status \"\$EVENT_HEAD_SHA\" \"\$HEAD_REF\"" "$workflow"
grep -qF "bash \"\$RUNNER_TEMP/changelog-branch-update.sh\" push \"\$EVENT_HEAD_SHA\" \"\$HEAD_REF\"" "$workflow"

if grep -qF 'bash scripts/changelog-branch-update.sh' "$workflow"; then
  echo 'reusable workflow still loads its helper from the caller repository' >&2
  exit 1
fi

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

caller="$test_root/external-consumer"
remote="$test_root/external-consumer.git"
runner_temp="$test_root/runner-temp"

git init -q --bare "$remote"
git init -q -b main "$caller"
git -C "$caller" config user.name 'Fixture Author'
git -C "$caller" config user.email fixture@example.com
printf 'external consumer\n' > "$caller/README.md"
git -C "$caller" add README.md
git -C "$caller" commit -q -m 'feat: external consumer'
git -C "$caller" checkout -q -b feature
git -C "$caller" remote add origin "$remote"
git -C "$caller" push -q origin main feature

test ! -e "$caller/scripts/changelog-branch-update.sh"

mkdir -p "$runner_temp"
install -m 0755 "$repo_root/scripts/changelog-branch-update.sh" "$runner_temp/changelog-branch-update.sh"

expected_head=$(git -C "$caller" rev-parse HEAD)
status=$(
  cd "$caller"
  bash "$runner_temp/changelog-branch-update.sh" status "$expected_head" feature
)
test "$status" = current

echo 'external changelog consumer contract passed'
