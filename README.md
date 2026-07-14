# Developer Workspace

Private image and workstation tooling for the K3s-hosted iPad Developer Workspace.

## Scope

This repository owns the versioned container image, shared CLI baseline,
code-server defaults, smoke tests, and dependency automation. Personal
configuration is applied explicitly from a private chezmoi repository and
persists in the mounted home. Kubernetes, Cloudflare, storage, RBAC, backup,
and observability live in `ignazio-ingenito/homelab`.

Source issues: `ignazio-ingenito/homelab#297` and
`ignazio-ingenito/homelab#300`.

## Build

```bash
make build
make smoke
```

The operator bootstrap, credential boundaries, tmux recovery flow, and live
acceptance checks are documented in `docs/OPERATOR-BOOTSTRAP.md`.

Tool ownership, version inspection, and update behavior are documented in
`docs/TOOL-LIFECYCLE.md`. Run `workspace-tools` to inspect the active tool
inventory and `workspace-tools update` to update runtime-managed tools.

## Work on two repositories at the same time

Keep each repository in its own browser tab and tmux session. The example below
uses `repo-a` for the project already open and `repo-b` for the second
project. Replace `OWNER` and `repo-b` with the real GitHub owner and
repository name.

### 1. Leave the current project running

If Codex is already working in `repo-a`, leave that browser tab and its
terminal unchanged. Do not use **File > Open Folder** in that tab.

Open a new browser tab:

```text
https://dev.skunklabs.uk/?folder=/workspaces
```

In the new tab, choose **Terminal > New Terminal**.

### 2. Clone the second repository

Run these commands in the new terminal:

```bash
git clone git@github.com:OWNER/repo-b.git /workspaces/repo-b
tmux new-session -d -s repo-b -c /workspaces/repo-b
```

The first project continues running in the original tab.

### 3. Open the second project

In the second browser tab, open:

```text
https://dev.skunklabs.uk/?folder=/workspaces/repo-b
```

Open a terminal in that tab and attach to the new tmux session:

```bash
tmux attach -t repo-b
```

Then start Codex inside tmux:

```bash
codex
```

You can now work on both repositories without mixing their terminals or Codex
sessions.

### Return to a session later

List the available tmux sessions:

```bash
tmux ls
```

Reconnect to the second project:

```bash
tmux attach -t repo-b
```

To leave tmux without stopping Codex, press `Ctrl+B`, release the keys, and
then press `D`.

### If both projects run services

Use different host ports. For example, run one application on port `3000` and
the other on `3001`. Two services cannot listen on the same port at the same
time.

## Release flow

1. GitHub Actions builds and tests an immutable image.
2. The image is published to GHCR.
3. The accepted version is replicated/imported into Harbor.
4. `homelab` references the exact Harbor tag.

No credentials belong in this repository or image.
