#!/usr/bin/env bash
set -u

failures=0
warnings=0

pass() { printf 'ok: %s\n' "$1"; }
warn() { printf 'warning: %s\n' "$1" >&2; warnings=$((warnings + 1)); }
fail() { printf 'error: %s\n' "$1" >&2; failures=$((failures + 1)); }

for binary in bash git gh tmux mise chezmoi codex bw sops age ssh ssh-agent code-server; do
  if command -v "$binary" >/dev/null 2>&1; then
    pass "$binary is available"
  else
    fail "$binary is missing"
  fi
done

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
