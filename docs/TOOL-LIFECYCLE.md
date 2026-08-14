# Workspace tools

Most command-line tools live in the persistent, writable home and are owned
directly by [mise](https://mise.jdx.dev/), using the baseline in
`config/mise/workspace-tools.toml`.

## Commands

```bash
mise ls          # installed and active tools
mise doctor      # native diagnostics
mise install     # install tools declared by the active configuration
mise self-update --yes
mise upgrade     # update within declared version ranges
codex update     # update only Codex
hash -r
```

Project-specific versions remain owned by each repository through its
`mise.toml`. Prefer `mise exec` in CI and scripts; interactive shells activate
mise from `.bashrc`.

## Ownership

| Owner | Tools | Location | Update |
| --- | --- | --- | --- |
| Persistent home via mise | Node, Python, uv, GitHub CLI, chezmoi, Bitwarden CLI, SOPS, age, kubectl, Helm, kustomize, Argo CD, OpenTofu, Ansible, jq, yq, actionlint, Trivy, ripgrep, fd, ShellCheck | `~/.local/share/mise` | `mise install`, `mise upgrade` |
| Persistent home | Codex | `~/.local/libexec/codex` | automatic before a new session, or `codex update` |
| Image bootstrap | code-server, Bash, Git, SSH, tmux, curl, GnuPG, browser runtime libraries, recovery copy of mise | `/usr`, `/usr/local`, `/opt` | image rebuild and rollout |
| Project | Repository-specific versions | repository `mise.toml` | reviewed repository change |

The image contains a pinned, SHA-256-verified recovery copy of mise. The
launcher copies it to `~/.local/bin/mise` only when the persistent home has no
usable binary. Chromium itself is not bundled; projects own their browser
version and cache while the image provides root-owned runtime libraries.

## Startup and recovery

The entrypoint runs this idempotent native sequence in the persistent home:

```bash
mise install node python uv
mise install
codex --version
```

Languages required by npm/pipx backends are installed first. A registry outage
does not block code-server: installed tools remain usable. Retry with
`mise install` and `codex update`.

`workspace-doctor` keeps workspace-specific checks and delegates generic
tool-manager diagnostics to `mise doctor`.

## Codex availability-first launcher

Starting `codex` checks for an update when the last successful check is older
than six hours. A failed update keeps an existing binary usable and backs off
for fifteen minutes. A first installation fails only when no binary exists.

```bash
CODEX_AUTO_UPDATE=true
CODEX_AUTO_UPDATE_INTERVAL=21600
CODEX_AUTO_UPDATE_FAILURE_BACKOFF=900
CODEX_AUTO_UPDATE_TIMEOUT=120
```

After a successful standalone installation, the launcher archives a historical
`~/.local/bin/codex` shim so it cannot shadow `/usr/local/bin/codex`.

## Boundary with CI runners

Developer Workspace and CI runners are separate products. The interactive tool
catalog does not justify a custom runner image. CI jobs should use
repository-owned declarations, standard setup actions or package managers
unless a measured technical constraint requires otherwise.

## Upstream references

- [mise installation guidance](https://mise.jdx.dev/installing-mise.html)
- [mise install](https://mise.jdx.dev/cli/install.html)
- [mise upgrade](https://mise.jdx.dev/cli/upgrade.html)
- [mise self-update](https://mise.jdx.dev/cli/self-update.html)
- [mise getting started and doctor](https://mise.jdx.dev/getting-started)
