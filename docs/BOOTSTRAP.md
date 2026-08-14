# Repository bootstrap

1. Keep `main` protected and require the current CI verification before merge.
2. Allow GitHub Actions to publish immutable GHCR packages from trusted `main` runs.
3. Open implementation pull requests referencing `ignazio-ingenito/homelab#297` when the change belongs to that original scope.
4. Change pinned tool versions only through reviewed pull requests.
5. Verify downloaded standalone binaries according to their upstream integrity mechanism before relying on them in production.
6. Do not treat Harbor promotion as a release prerequisite: the producer publishes the verified immutable artifact to GHCR, while Homelab consumes it through Harbor's authenticated `private-ghcr` Proxy Cache.
7. Before deployment, verify producer CI success, immutable release identity and the corresponding Homelab reference; retain the previous known-good identity for rollback.
