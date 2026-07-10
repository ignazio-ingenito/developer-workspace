#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: download-verified.sh <asset-url> <checksum-url> <asset-name> <output>" >&2
  exit 2
fi

asset_url=$1
checksum_url=$2
asset_name=$3
output=$4

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

asset_path="$tmp_dir/$asset_name"
checksum_path="$tmp_dir/checksums"

curl -fsSL "$asset_url" -o "$asset_path"
curl -fsSL "$checksum_url" -o "$checksum_path"

if grep -Eq '^[[:xdigit:]]{64}([[:space:]]+|$)' "$checksum_path"; then
  if [[ $(wc -w < "$checksum_path") -eq 1 ]]; then
    expected=$(tr -d '[:space:]' < "$checksum_path")
  else
    expected=$(awk -v name="$asset_name" '$NF == name || $NF == "*" name {print $1; exit}' "$checksum_path")
  fi
else
  echo "checksum file has an unsupported format: $checksum_url" >&2
  exit 1
fi

if [[ -z "${expected:-}" ]]; then
  echo "checksum for $asset_name not found in $checksum_url" >&2
  exit 1
fi

actual=$(sha256sum "$asset_path" | awk '{print $1}')
if [[ "$actual" != "$expected" ]]; then
  echo "checksum mismatch for $asset_name" >&2
  echo "expected: $expected" >&2
  echo "actual:   $actual" >&2
  exit 1
fi

install -m 0644 "$asset_path" "$output"
