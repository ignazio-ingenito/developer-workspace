# Changelog

All notable changes to this project are documented in this file.

## Unreleased


### Features

- **image:** Add the base Developer Workspace image (#1)
- **workspace:** Bootstrap versioned code-server image (#2)
- **release:** Verify downloaded tool checksums (#3)
- **workspace:** Bootstrap operator environment (#5)
- **tools:** Manage writable workspace tool lifecycle (#7)
- **image:** Add DNS utilities (#8)
- **changelog:** Centralize automation
- **workspace:** Add browser runtime and iteration CLI baseline


### Bug fixes

- **changelog:** Skip Dependabot pull requests (#11)
- **ci:** Guard changelog checkout against missing head branch


### Documentation

- **readme:** Add parallel repository workflow (#6)
- Document personal ssh agent setup
- **changelog:** Document public caller access
- Define availability-first image CI design
- Plan availability-first image CI
- Keep unfixed CVEs visible in CI
- Split Trivy reporting from blocking gate


### Tests

- **changelog:** Satisfy shellcheck


### CI

- Publish latest and immutable sha images (#4)
- Update checkout action to v5
- Scan and publish exact workspace image artifact
- Isolate verification from package publication


### Maintenance

- Initialize developer workspace repository
- Merge pull request #10 from ignazio-ingenito/agent/centralize-changelog

feat(changelog): centralize git-cliff automation
