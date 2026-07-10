#!/usr/bin/env bash
set -euo pipefail

required=(code-server bash git gh tmux mise chezmoi sops age kubectl helm kustomize tofu ansible jq yq rg ssh)
for binary in "${required[@]}"; do
  command -v "$binary" >/dev/null || { echo "missing: $binary" >&2; exit 1; }
done

test "$(id -u)" != "0"
test "${BW_SERVER:-}" = "https://vault.skunklabs.uk"
code-server --version
mise --version
sops --version
kubectl version --client=true
helm version --short
kustomize version
tofu version
chezmoi --version

echo "smoke test passed"
