# Workspace tools

Most command-line tools live in the persistent, writable home. They survive a
Pod restart and can be updated without rebuilding the Developer Workspace
image.

## The two commands to remember

Show every tool, its version, owner, update method, and active path:

```bash
workspace-tools
```

Update `mise`, all tools managed by `mise`, and Codex:

```bash
workspace-tools update
hash -r
```

Open a new terminal after the update if an old terminal still resolves a
previous command path.

## Where tools live

| Owner | Tools | Location | Update |
| --- | --- | --- | --- |
| Persistent home | mise, Node, Python 3, uv, GitHub CLI, chezmoi, Bitwarden CLI, SOPS, age, kubectl, Helm, kustomize, Argo CD, OpenTofu, Ansible, jq, yq, actionlint, Trivy, ripgrep, fd, ShellCheck | `~/.local` and `~/.local/share/mise` | `workspace-tools update` |
| Persistent home | Codex | `~/.local/libexec/codex` | Automatically before a new Codex session, or `workspace-tools update` |
| Image bootstrap | code-server, Bash, Git, SSH, tmux, curl, GnuPG, Chromium/Playwright runtime libraries and recovery utilities | `/usr` and `/usr/local` | Image rebuild and rollout |
| Project | Versions required by one repository | The repository's `mise.toml` | Change and commit `mise.toml` |

The image contains a small recovery copy of `mise`. On first use it is copied
to `~/.local/bin/mise`; that writable copy is the active binary and can update
itself.

The workspace Python default is constrained to major version `3`, so
`workspace-tools update` may advance both patch and minor releases while a
future major-version change remains explicit.

Chromium itself is not bundled in the image. Repositories such as those using
Playwright keep ownership of their browser version and cache; the immutable
image supplies the Debian runtime libraries and fonts that require root access.

## Boundary with CI runners

Developer Workspace and CI runners are separate products with independent
requirements and lifecycles.

- Developer Workspace is a persistent, human-operated code-server environment.
  Its broad tool catalog exists for interactive convenience, recovery and
  availability.
- CI runners are execution infrastructure for automated jobs. Their base image
  should contain only what the runner runtime or technical runner class actually
  requires; workflow- or project-specific tools belong in the workflow or the
  repository and should use standard upstream setup/actions or package managers
  where practical.
- A tool being available in Developer Workspace is **not** evidence that it
  belongs in a CI runner image. CI customization requires an independent,
  measurable need such as startup cost, reliability or a technical constraint.
- The Developer Workspace image must not be used as a CI runner base merely to
  make the two environments look alike, and CI runner requirements must not
  expand the Developer Workspace image unless the workspace itself needs them.
- Repository-owned tool configuration such as `mise.toml` may be shared between
  interactive development and CI when it genuinely describes the project's
  toolchain. This does not create a shared base-image or lifecycle contract.

The intended common layer is therefore the **project tool contract**, when one
exists, not a universal workstation/runner image.

## First start after deploying the image

The entrypoint installs missing home tools and migrates Codex once. On later
starts it skips this step unless the workspace tool list changed or Codex is
missing.

If the package registry is temporarily unavailable, code-server still starts.
Retry from a terminal:

```bash
workspace-tools update
hash -r
workspace-doctor
```

The first installation can take a few minutes. Existing tools remain usable if
a later update fails.

## Codex automatic updates

Starting `codex` checks for a newer standalone release when the last successful
check is older than six hours. It never restarts a Codex process that is already
running. A new process uses the updated version.

Update only Codex immediately with:

```bash
workspace-tools update codex
```

Automatic checks use these defaults:

```bash
CODEX_AUTO_UPDATE=true
CODEX_AUTO_UPDATE_INTERVAL=21600
CODEX_AUTO_UPDATE_FAILURE_BACKOFF=900
CODEX_AUTO_UPDATE_TIMEOUT=120
```

If an update fails and Codex is already installed, the launcher warns and uses
the installed version. A first installation fails only when no usable Codex
binary exists.

## Migrating an older workspace

After deploying this image over an existing persistent home, run:

```bash
workspace-tools update
hash -r
workspace-tools
workspace-doctor
```

The command removes or archives the old npm-managed Codex command only after
the standalone installation succeeds. Do not use `sudo npm install --global`
to update workspace tools.

## Project-specific versions

The workspace list provides convenient defaults. A repository remains free to
pin another version in its own `mise.toml`:

```bash
cd /workspaces/my-project
mise use node@24
mise install
```

Commit the repository's `mise.toml` so interactive development and CI can use
the same project toolchain when that is useful, without coupling their base
images.
