#!/usr/bin/env bash
set -euo pipefail

workflow=.github/workflows/changelog-reusable.yml

grep -qF "github.actor != 'dependabot[bot]'" "$workflow"
grep -qF "github.actor != 'renovate[bot]'" "$workflow"
