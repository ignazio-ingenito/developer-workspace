# Harbor promotion

The release workflow publishes immutable tags to GHCR. Promote the accepted tag to Harbor and verify that the digest is unchanged before updating `homelab`.

Example shape:

```bash
skopeo copy \
  docker://ghcr.io/ignazio-ingenito/developer-workspace:v0.1.0 \
  docker://harbor.lab.skunklabs.uk/<project>/developer-workspace:v0.1.0
```

Credentials must come from the operator environment or Vaultwarden and must never be committed.

After copying:

1. compare the GHCR and Harbor digests;
2. run the image smoke test from the Harbor reference;
3. update `homelab` to the exact Harbor tag or digest;
4. retain the previous known-good tag for rollback.
