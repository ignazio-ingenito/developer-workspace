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
- **workspace:** Update code-server base to 4.132.0
- **ci:** Align standard image checks


### Documentation

- **readme:** Add parallel repository workflow (#6)
- Document personal ssh agent setup
- **changelog:** Document public caller access
- Define availability-first image CI design
- Plan availability-first image CI
- Keep unfixed CVEs visible in CI
- Split Trivy reporting from blocking gate
- Document least-privilege publish split
- Align plan with least-privilege verification
- Archive completed availability-first plan
- Archive superseded availability-first design
- Remove archived availability-first plan from active path
- Remove archived availability-first design from active path


### Tests

- **changelog:** Satisfy shellcheck
- Define availability-first Trivy policy contract


### CI

- Publish latest and immutable sha images (#4)
- Update checkout action to v5
- Scan and publish exact workspace image artifact
- Isolate verification from package publication
- Classify fixable Trivy findings deterministically
- Make Trivy availability gate deterministic
- Make Trivy jq filter shellcheck-safe
- Use standard Docker metadata and Trivy gates
- Remove custom Trivy policy parser
- Remove custom Trivy policy test
- Scope Trivy gate exceptions to upstream paths


### Maintenance

- Initialize developer workspace repository
- Merge pull request #10 from ignazio-ingenito/agent/centralize-changelog

feat(changelog): centralize git-cliff automation
- Remove unused inherited fixuid
- Document temporary upstream CVE exceptions
- Merge pull request #18 from ignazio-ingenito/wave-16-availability-first-ci

ci: gate fixable CVEs on the exact workspace image
- Build workspace from Debian slim
- **deps:** Update docker/dockerfile docker tag to v1.26
