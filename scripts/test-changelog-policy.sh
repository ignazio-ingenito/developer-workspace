#!/usr/bin/env bash
set -euo pipefail

workflow=.github/workflows/changelog-reusable.yml
helper=scripts/changelog-branch-update.sh

grep -qF "github.actor != 'ignazio-changelog[bot]'" "$workflow"
grep -qF "github.actor != 'dependabot[bot]'" "$workflow"
grep -qF "github.actor != 'renovate[bot]'" "$workflow"
grep -qF 'id: freshness' "$workflow"
grep -qF 'bash scripts/changelog-branch-update.sh status "$EVENT_HEAD_SHA" "$HEAD_REF"' "$workflow"
grep -qF "steps.freshness.outputs.stale != 'true'" "$workflow"
grep -qF 'id: git-cliff-first' "$workflow"
grep -qF 'continue-on-error: true' "$workflow"
grep -qF "steps.git-cliff-first.outcome == 'failure'" "$workflow"
test "$(grep -cF 'uses: orhun/git-cliff-action@f50e11560dce63f7c33227798f90b924471a88b5' "$workflow")" -eq 2
grep -qF 'bash scripts/changelog-branch-update.sh push "$EVENT_HEAD_SHA" "$HEAD_REF"' "$workflow"

test -f "$helper"
if grep -Eq 'pull_request_target|git add \.|git push .*--force|--force-with-lease|\[skip ci\]' "$workflow" "$helper"; then
  echo 'unsafe changelog workflow pattern found' >&2
  exit 1
fi
