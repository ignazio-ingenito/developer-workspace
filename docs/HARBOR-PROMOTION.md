# Harbor promotion

The release workflow publishes to GHCR. Promotion to Harbor must copy the exact immutable version, for example with `skopeo copy`, and then verify the digest before updating `homelab`.

Example shape:

```bash
skopeo copy \
  docker://ghcr.io/ignazio-ingenito/developer-workspace:v0.1.0 \
  docker://harbor.lab.skunklabs.uk/<project>/developer-workspace:v0.1.0
```

Credentials must come from the operator environment or Vaultwarden and must not be committed.
