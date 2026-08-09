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


### Bug fixes

- **changelog:** Skip Dependabot pull requests (#11)
- **changelog:** Checkout pull request head SHA


### Documentation

- **readme:** Add parallel repository workflow (#6)
- Document personal ssh agent setup
- **changelog:** Document public caller access


### Tests

- **changelog:** Satisfy shellcheck


### CI

- Publish latest and immutable sha images (#4)
- Update checkout action to v5


### Maintenance

- Initialize developer workspace repository
- Merge pull request #10 from ignazio-ingenito/agent/centralize-changelog

feat(changelog): centralize git-cliff automation
