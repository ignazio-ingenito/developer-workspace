#!/usr/bin/env bash
set -euo pipefail

workspace-tools bootstrap
eval "$(mise activate bash)"

required=(code-server bash git gh tmux mise chezmoi sops age kubectl helm kustomize tofu ansible jq yq rg fd ssh codex workspace-tools bw node npm python3 uv shellcheck workspace-doctor workspace-tmux)
for binary in "${required[@]}"; do
  command -v "$binary" >/dev/null || { echo "missing: $binary" >&2; exit 1; }
done

test "$(id -u)" != "0"
test "${BW_SERVER:-}" = "https://vault.skunklabs.uk"
test -d /opt/oh-my-bash
test "$(command -v codex)" = /usr/local/bin/codex
test -x "${HOME}/.local/bin/mise"
case $(command -v gh) in
  "$HOME"/*) ;;
  *) echo "gh is not active from the persistent home" >&2; exit 1 ;;
esac

code-server --version
workspace-tools status
bw --version
mise --version
sops --version
kubectl version --client=true
helm version --short
kustomize version
tofu version
chezmoi --version

/usr/local/lib/developer-workspace/test-shell-bootstrap.sh
/usr/local/lib/developer-workspace/test-workspace-tools.sh

code-server --extensions-dir /opt/developer-workspace/code-server-extensions --list-extensions \
  | grep -Fx redhat.vscode-yaml

echo "smoke test passed"
