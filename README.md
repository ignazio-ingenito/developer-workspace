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

## Release flow

1. GitHub Actions builds and tests an immutable image.
2. The image is published to GHCR.
3. The accepted version is replicated/imported into Harbor.
4. `homelab` references the exact Harbor tag.

No credentials belong in this repository or image.
