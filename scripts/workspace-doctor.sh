#!/usr/bin/env bash
set -u

failures=0
warnings=0
codex_install_dir=${CODEX_INSTALL_DIR:-${HOME}/.local/libexec/codex}
codex_real="$codex_install_dir/codex"

pass() { printf 'ok: %s\n' "$1"; }
warn() { printf 'warning: %s\n' "$1" >&2; warnings=$((warnings + 1)); }
fail() { printf 'error: %s\n' "$1" >&2; failures=$((failures + 1)); }

for binary in bash git gh tmux mise chezmoi codex workspace-tools bw sops age kubectl helm kustomize argocd tofu ansible jq yq actionlint trivy rg fd shellcheck node npm python3 uv ssh ssh-agent code-server; do
  if command -v "$binary" >/dev/null 2>&1; then
    pass "$binary is available"
  else
    fail "$binary is missing"
  fi
done

if [[ -x ${HOME}/.local/bin/mise ]]; then
  pass "mise active binary is in persistent home"
else
  fail "mise active binary is missing from ~/.local/bin; run workspace-tools update"
fi

for binary in gh chezmoi bw sops age kubectl helm kustomize argocd tofu ansible jq yq actionlint trivy rg fd shellcheck node npm python3 uv; do
  binary_path=$(command -v "$binary" 2>/dev/null || true)
  case $binary_path in
    "$HOME"/*) pass "$binary is active from persistent home" ;;
    *) fail "$binary must be active from persistent home; run workspace-tools update and open a new shell" ;;
  esac
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
  if ldconfig -p 2>/dev/null | grep -Fq "$library"; then
    pass "$library browser runtime library is available"
  else
    fail "$library browser runtime library is missing; rebuild the workspace image"
  fi
done

if [[ $(command -v codex 2>/dev/null) == /usr/local/bin/codex ]]; then
  pass "Codex uses the managed launcher"
else
  fail "Codex must resolve to /usr/local/bin/codex; run workspace-tools update and hash -r"
fi

if [[ -x $codex_real ]]; then
  pass "Codex standalone installation is present in persistent home"
  pass "Codex active version is $("$codex_real" --version 2>/dev/null)"
else
  warn "Codex standalone installation is absent; the first Codex launch will install it"
fi

if [[ -e ${HOME}/.local/bin/codex || -L ${HOME}/.local/bin/codex ]]; then
  fail "legacy Codex command in ~/.local/bin shadows the managed launcher; run workspace-tools update"
fi

if [[ -d /usr/local/lib/node_modules/@openai/codex ]]; then
  fail "legacy image-owned npm Codex installation is still present"
fi

if workspace-tools status >/dev/null 2>&1; then
  pass "workspace-tools can inspect the tool inventory"
else
  fail "workspace-tools status failed"
fi

if [[ ${BW_SERVER:-} == "https://vault.skunklabs.uk" ]]; then
  pass "Bitwarden server is vault.skunklabs.uk"
else
  fail "BW_SERVER must be https://vault.skunklabs.uk"
fi

if [[ -d ${HOME}/.ssh && $(stat -c '%a' "${HOME}/.ssh" 2>/dev/null) == 700 ]]; then
  pass "SSH directory permissions are 700"
else
  fail "SSH directory must exist with mode 700"
fi

if [[ -f ${HOME}/.bashrc ]]; then
  if grep -Eq 'plugins=\([^)]*([[:space:]]|^)mise([[:space:]]|\))' "${HOME}/.bashrc"; then
    fail ".bashrc requests the unavailable Oh My Bash mise plugin"
  fi
  if grep -Eq 'aliases=\([^)]*([[:space:]]|^)git([[:space:]]|\))' "${HOME}/.bashrc"; then
    fail ".bashrc requests the unavailable Oh My Bash git alias module"
  fi
  # The command substitution is intentionally matched as literal text.
  # shellcheck disable=SC2016
  if grep -Fq 'eval "$(mise activate bash)"' "${HOME}/.bashrc"; then
    pass "mise is activated by .bashrc"
  else
    warn "mise activation is absent from .bashrc"
  fi
else
  fail ".bashrc is missing"
fi

if [[ -f ${HOME}/.tmux.conf ]]; then
  pass ".tmux.conf exists"
else
  fail ".tmux.conf is missing"
fi

if [[ -d ${HOME}/.local/share/code-server/extensions ]]; then
  pass "code-server extension directory is in persistent home"
else
  fail "persistent code-server extension directory is missing"
fi

if [[ -n ${SSH_AUTH_SOCK:-} && -S ${SSH_AUTH_SOCK} ]]; then
  pass "ssh-agent is reachable"
else
  warn "ssh-agent is not active in this shell"
fi

if ((failures > 0)); then
  printf '%d error(s), %d warning(s)\n' "$failures" "$warnings" >&2
  exit 1
fi

printf 'workspace baseline is healthy (%d warning(s))\n' "$warnings"
