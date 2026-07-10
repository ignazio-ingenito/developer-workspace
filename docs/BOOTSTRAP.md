# Repository bootstrap

1. Create the private repository `ignazio-ingenito/developer-workspace` with `main` as the default branch.
2. Enable GitHub Actions package write permission.
3. Protect `main` and require the `build` job.
4. Open the first implementation PR referencing `ignazio-ingenito/homelab#297`.
5. Review and validate every pinned tool version before release.
6. Add SHA-256 verification for all downloaded standalone binaries before the first production tag.
7. Tag releases as `vMAJOR.MINOR.PATCH`; the workflow publishes only immutable version tags.

The initial scaffold is intentionally a bootstrap release candidate, not a production image, until checksum verification and a successful CI build are complete.
