#!/usr/bin/env bash
set -euo pipefail

workspace-tools bootstrap
eval "$(mise activate bash)"

required=(code-server bash git gh tmux mise chezmoi sops age kubectl helm kustomize tofu ansible jq yq rg fd ssh dig codex workspace-tools bw node npm python3 uv shellcheck workspace-doctor workspace-tmux argocd actionlint trivy)
for binary in "${required[@]}"; do
  command -v "$binary" >/dev/null || { echo "missing: $binary" >&2; exit 1; }
done

browser_runtime_libs=(
  libglib-2.0.so.0
  libgobject-2.0.so.0
  libnss3.so
  libatk-1.0.so.0
  libdbus-1.so.3
  libgbm.so.1
  libxkbcommon.so.0
  libasound.so.2
  libX11.so.6
)
for library in "${browser_runtime_libs[@]}"; do
  ldconfig -p | grep -Fq "$library" || {
    echo "missing browser runtime library: $library" >&2
    exit 1
  }
done

grep -Fxq 'python = "3"' /opt/developer-workspace/mise-workspace-tools.toml

test "$(id -u)" != "0"
test "${BW_SERVER:-}" = "https://vault.skunklabs.uk"
test -d /opt/oh-my-bash
test "$(command -v codex)" = /usr/local/bin/codex
test -x "${HOME}/.local/bin/mise"
case $(command -v gh) in
  "$HOME"/*) ;;
  *) echo "gh is not active from the persistent home" >&2; exit 1 ;;
esac
for binary in argocd actionlint trivy jq yq ansible tofu python3; do
  case $(command -v "$binary") in
    "$HOME"/*) ;;
    *) echo "$binary is not active from the persistent home" >&2; exit 1 ;;
  esac
done

code-server --version
workspace-tools status
bw --version
mise --version
sops --version
kubectl version --client=true
helm version --short
kustomize version
tofu version
argocd version --client
trivy --version
actionlint -version
chezmoi --version

/usr/local/lib/developer-workspace/test-shell-bootstrap.sh
/usr/local/lib/developer-workspace/test-workspace-tools.sh

code-server --extensions-dir /opt/developer-workspace/code-server-extensions --list-extensions \
  | grep -Fx redhat.vscode-yaml

echo "smoke test passed"
