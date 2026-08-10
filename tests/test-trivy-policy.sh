#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="${repo_root}/scripts/check-trivy-policy.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"${tmp_dir}/mixed.json" <<'JSON'
{
  "Results": [
    {
      "Target": "debian 13",
      "Vulnerabilities": [
        {
          "VulnerabilityID": "CVE-FIXABLE",
          "PkgName": "openssl",
          "InstalledVersion": "1.0",
          "FixedVersion": "1.1",
          "Severity": "HIGH"
        },
        {
          "VulnerabilityID": "CVE-UNFIXED",
          "PkgName": "libexample",
          "InstalledVersion": "2.0",
          "FixedVersion": "",
          "Severity": "CRITICAL"
        }
      ]
    }
  ]
}
JSON

set +e
mixed_output="$(bash "$checker" "${tmp_dir}/mixed.json" 2>&1)"
mixed_status=$?
set -e

if [[ $mixed_status -eq 0 ]]; then
  echo "expected a fixable HIGH vulnerability to fail the policy" >&2
  exit 1
fi

grep -F $'FIXABLE\tHIGH\tCVE-FIXABLE\tdebian 13\topenssl\t1.0\t1.1' <<<"$mixed_output" >/dev/null
grep -F $'UNFIXED\tCRITICAL\tCVE-UNFIXED\tdebian 13\tlibexample\t2.0\t-' <<<"$mixed_output" >/dev/null
grep -F 'fixable=1 unfixed=1' <<<"$mixed_output" >/dev/null

cat >"${tmp_dir}/unfixed-only.json" <<'JSON'
{
  "Results": [
    {
      "Target": "node-pkg",
      "Vulnerabilities": [
        {
          "VulnerabilityID": "CVE-UNFIXED-ONLY",
          "PkgName": "example",
          "InstalledVersion": "3.0",
          "Severity": "HIGH"
        }
      ]
    }
  ]
}
JSON

unfixed_output="$(bash "$checker" "${tmp_dir}/unfixed-only.json")"
grep -F $'UNFIXED\tHIGH\tCVE-UNFIXED-ONLY\tnode-pkg\texample\t3.0\t-' <<<"$unfixed_output" >/dev/null
grep -F 'fixable=0 unfixed=1' <<<"$unfixed_output" >/dev/null

echo "Trivy availability-first policy tests passed."
