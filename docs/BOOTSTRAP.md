# Repository bootstrap

1. Keep `main` protected and require the `build` job before merge.
2. Allow GitHub Actions to publish packages for tagged releases.
3. Open implementation pull requests referencing `ignazio-ingenito/homelab#297`.
4. Change pinned tool versions only through reviewed pull requests.
5. Add SHA-256 verification for every downloaded standalone binary before the first production release.
6. Do not tag a production release until CI, checksum verification, GHCR publication, and Harbor promotion have been validated.
