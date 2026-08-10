#!/usr/bin/env bash
set -euo pipefail

report="${1:-}"
if [[ -z "$report" || ! -f "$report" ]]; then
  echo "usage: $0 <trivy-report.json>" >&2
  exit 2
fi

jq -e '.Results | type == "array"' "$report" >/dev/null

jq_filter='[
  .Results[]? as $result
  | ($result.Vulnerabilities // [])[]
  | select(.Severity == "HIGH" or .Severity == "CRITICAL")
  | {
      status: (if ((.FixedVersion // "") | length) > 0 then "FIXABLE" else "UNFIXED" end),
      severity: .Severity,
      id: .VulnerabilityID,
      target: $result.Target,
      package: .PkgName,
      installed: .InstalledVersion,
      fixed: (if ((.FixedVersion // "") | length) > 0 then .FixedVersion else "-" end)
    }
]'

printf 'STATUS\tSEVERITY\tCVE\tTARGET\tPACKAGE\tINSTALLED\tFIXED\n'
jq -r "${jq_filter} | sort_by(.status, .severity, .id)[] | [.status, .severity, .id, .target, .package, .installed, .fixed] | @tsv" "$report"

fixable_count="$(jq -r "${jq_filter} | map(select(.status == \"FIXABLE\")) | length" "$report")"
unfixed_count="$(jq -r "${jq_filter} | map(select(.status == \"UNFIXED\")) | length" "$report")"

echo "Trivy HIGH/CRITICAL summary: fixable=${fixable_count} unfixed=${unfixed_count}"

if (( fixable_count > 0 )); then
  echo "Blocking: ${fixable_count} HIGH/CRITICAL vulnerabilities have a fixed version available." >&2
  exit 1
fi

echo "Availability-first gate passed: no fixable HIGH/CRITICAL vulnerabilities found."
