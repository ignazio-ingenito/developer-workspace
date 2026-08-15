#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_BOOTSTRAP=false /usr/local/lib/developer-workspace/entrypoint.sh true
cd "$HOME"
mise install node python uv
mise install
eval "$(mise activate bash)"

required=(code-server bash git gh tmux mise chezmoi sops age kubectl helm kustomize tofu ansible jq yq rg fd ssh dig codex bw node npm python3 uv shellcheck workspace-doctor workspace-tmux argocd actionlint trivy)
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
  ldconfig -p | grep -F "$library" >/dev/null || {
    echo "missing browser runtime library: $library" >&2
    exit 1
  }
done

grep -Fxq 'python = "3"' /opt/developer-workspace/mise-workspace-tools.toml
test "$(id -u)" != "0"
test "${BW_SERVER:-}" = "https://vault.skunklabs.uk"
test -d /opt/oh-my-bash
test "$(command -v codex)" = /usr/local/bin/codex
test -x "$HOME/.local/bin/mise"
test ! -e "$HOME/.local/bin/codex"

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
mise --version
codex --version
bw --version
sops --version
kubectl version --client=true
helm version --short
kustomize version
tofu version
argocd version --client
trivy --version
actionlint --version
chezmoi --version
workspace-doctor

code-server --extensions-dir /opt/developer-workspace/code-server-extensions --list-extensions \
  | grep -Fx redhat.vscode-yaml

# One end-to-end preservation check: the entrypoint seeds a new persistent home
# and never overwrites user-owned shell or extension state on later starts.
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
test_home="$test_root/home"
test_workspaces="$test_root/workspaces"
test_extensions="$test_root/extensions"
mkdir -p "$test_home" "$test_extensions/redhat.vscode-yaml-test"
printf '%s\n' baseline > "$test_extensions/redhat.vscode-yaml-test/source"

HOME="$test_home" \
WORKSPACES_ROOT="$test_workspaces" \
WORKSPACE_BOOTSTRAP=false \
DEVELOPER_WORKSPACE_BASELINE_EXTENSIONS="$test_extensions" \
  /usr/local/lib/developer-workspace/entrypoint.sh true

test -f "$test_home/.bashrc"
test -f "$test_home/.tmux.conf"
test "$(stat -c '%a' "$test_home/.ssh")" = 700
grep -Fxq baseline "$test_home/.local/share/code-server/extensions/redhat.vscode-yaml-test/source"

printf '%s\n' '# user-owned' > "$test_home/.bashrc"
printf '%s\n' user-owned > "$test_home/.local/share/code-server/extensions/redhat.vscode-yaml-test/source"
HOME="$test_home" \
WORKSPACES_ROOT="$test_workspaces" \
WORKSPACE_BOOTSTRAP=false \
DEVELOPER_WORKSPACE_BASELINE_EXTENSIONS="$test_extensions" \
  /usr/local/lib/developer-workspace/entrypoint.sh true

grep -Fxq '# user-owned' "$test_home/.bashrc"
grep -Fxq user-owned "$test_home/.local/share/code-server/extensions/redhat.vscode-yaml-test/source"

echo "smoke test passed"
