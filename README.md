# Developer Workspace

Private image and workstation tooling for the K3s-hosted iPad Developer Workspace.

## Scope

This repository owns the versioned container image, shared CLI baseline, code-server defaults, smoke tests, and dependency automation. Kubernetes, Cloudflare, storage, RBAC, backup, and observability live in `ignazio-ingenito/homelab`.

Source issue: `ignazio-ingenito/homelab#297`.

## Build

```bash
make build
make smoke
```

## Release flow

1. GitHub Actions builds and tests an immutable image.
2. The image is published to GHCR.
3. The accepted version is replicated/imported into Harbor.
4. `homelab` references the exact Harbor tag.

No credentials belong in this repository or image.
