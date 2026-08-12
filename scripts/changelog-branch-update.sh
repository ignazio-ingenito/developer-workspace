#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
expected_head=${2:-}
head_ref=${3:-}
remote=${CHANGELOG_REMOTE:-origin}

usage() {
  echo "usage: $0 <status|push> <expected-head-sha> <head-ref>" >&2
}

if [[ -z "$mode" || -z "$expected_head" || -z "$head_ref" ]]; then
  usage
  exit 2
fi

remote_head() {
  local output
  if ! output=$(git ls-remote --heads "$remote" "refs/heads/$head_ref"); then
    echo "failed to read remote head for $head_ref" >&2
    return 1
  fi
  awk 'NR == 1 { print $1 }' <<<"$output"
}

current_head=$(remote_head)

case "$mode" in
  status)
    if [[ "$current_head" == "$expected_head" ]]; then
      echo current
    else
      echo stale
    fi
    ;;
  push)
    if [[ "$current_head" != "$expected_head" ]]; then
      echo "stale changelog run: remote head advanced" >&2
      exit 0
    fi

    if git push "$remote" "HEAD:refs/heads/$head_ref"; then
      exit 0
    fi

    current_head=$(remote_head)
    if [[ "$current_head" != "$expected_head" ]]; then
      echo "stale changelog run: remote head advanced during push" >&2
      exit 0
    fi

    echo "changelog push failed while remote head remained at expected SHA" >&2
    exit 1
    ;;
  *)
    usage
    exit 2
    ;;
esac
