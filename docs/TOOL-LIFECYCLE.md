# Workspace tool lifecycle

The Developer Workspace uses one command to inspect its tools:

```bash
workspace-tools
```

The output shows each tool's installed version, active path, owner, and update
method. To update every runtime-managed tool, run:

```bash
workspace-tools update
```

The command updates tools that are allowed to change in the running workspace.
It does not try to modify the read-only container filesystem.

## Ownership rules

Each tool has one owner and one active installation.

| Owner | Examples | Location | Update method |
| --- | --- | --- | --- |
| Image | code-server, operating-system utilities, GitHub CLI, kubectl, Helm, SOPS, OpenTofu, Bitwarden CLI, chezmoi, mise | `/usr` and `/usr/local` | Renovate and/or base-image refresh, image rebuild, and rollout |
| Persistent home | Codex | `~/.local/libexec/codex` and `~/.codex` | Automatic before a new Codex session |
| Project | Go, Python, Node, dbt, and other project toolchains | mise data directory | The repository's `mise.toml` |
| User configuration | Shell, Git preferences, and personal extensions | Persistent home | chezmoi or code-server |

Do not install a second copy of an image-owned tool in the persistent home.
Do not use `sudo npm install --global` to update tools in a running workspace.

## Codex automatic updates

`codex` is a small image-owned launcher. The real Codex standalone installation
lives in the persistent home.

Before a new Codex process starts, the launcher checks whether the last
successful update is older than six hours. When a check is due, it uses the
official standalone installer to install or update Codex. The installer uses a
lock, versioned release directories, and an atomic `current` link.

An update never restarts a Codex process that is already running. New sessions
use the new version. If the update service is temporarily unavailable, the
launcher warns and starts the installed version. Only a first installation with
no usable Codex binary fails closed.

Run an update immediately with:

```bash
workspace-tools update codex
```

Automatic checks can be configured with:

```bash
CODEX_AUTO_UPDATE=true
CODEX_AUTO_UPDATE_INTERVAL=21600
CODEX_AUTO_UPDATE_FAILURE_BACKOFF=900
```

The intervals are expressed in seconds. Set `CODEX_AUTO_UPDATE=false` only for
diagnostics or controlled tests.

## Migrating an older workspace home

Older workspace homes may contain an npm-managed Codex command in
`~/.local/bin`. After the new image is deployed, run:

```bash
workspace-tools update
hash -r
command -v codex
workspace-doctor
```

The update command installs standalone Codex first, then retires the legacy
user command. `command -v codex` must return:

```text
/usr/local/bin/codex
```

`workspace-doctor` reports an error if a legacy npm installation still shadows
the launcher.

## Image-owned updates

Image-owned tools are deliberately not changed in place. Renovate checks the
explicitly pinned versions in the repository and opens reviewable pull
requests. Debian packages are refreshed when the image is rebuilt from its
updated base. After a change passes the smoke tests, publish and roll out a new
immutable image.

`workspace-tools update` reports this boundary instead of attempting an update
that the read-only filesystem cannot persist.
