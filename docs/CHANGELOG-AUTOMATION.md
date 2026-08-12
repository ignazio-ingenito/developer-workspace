# Changelog automation

`developer-workspace` owns the reusable workflow at
`.github/workflows/changelog-reusable.yml`. Applicable repositories call it
from a minimal `pull_request` wrapper; they do not copy the git-cliff logic.

`developer-workspace` is public because public caller repositories can use
reusable workflows only from public repositories. Private callers can use this
same public workflow. Credentials remain caller-scoped Actions secrets and are
not stored in the reusable workflow repository.

The workflow checks out the pull request head branch with complete history,
regenerates `CHANGELOG.md`, and pushes `docs(changelog): update` to that same
branch only when the file changed. A repository-local `cliff.toml` overrides
the common configuration. External commands in local configurations are
disabled with `git-cliff --no-exec`.

## GitHub App

Create the dedicated GitHub App with these settings:

- name and slug: `ignazio-changelog`;
- repository permission: **Contents — Read and write**;
- all other repository and organization permissions: no access;
- webhook: disabled;
- installation: only the repositories where changelog automation applies.

For every installed repository, configure:

- Actions variable `CHANGELOG_APP_CLIENT_ID` with the App client ID;
- Actions secret `CHANGELOG_APP_PRIVATE_KEY` with the App private key.

Never commit the private key. The reusable workflow requests a token limited
to the current repository and `contents: write`, even if the App configuration
later gains additional permissions.

The GitHub App token is required because commits pushed with the repository
`GITHUB_TOKEN` do not automatically start the other CI workflows. App-authored
pushes do, so checks run against the new pull request head SHA.

## Deterministic branch updates

Before generating the changelog, the workflow compares the pull request event
SHA with the current remote branch head. A run whose head has already advanced
is stale: it exits successfully without generating or writing anything.

The final update is still a normal fast-forward push; force push and
`--force-with-lease` are not used. If the branch advances between the freshness
check and the push, the rejected push is reclassified as stale and the run ends
successfully without moving the branch. A push rejection while the remote head
is still the expected event SHA remains a real failure and keeps the check red.
The newer `synchronize` event is responsible for converging `CHANGELOG.md` on
the current pull request head.

`git-cliff` generation has at most two attempts. The second attempt covers a
transient provisioning/download failure; if it also fails, the workflow fails
normally rather than hiding a real generation problem.

## Security behavior

The changelog job is skipped for forks, non-PR events, the repository default
branch, Dependabot pull requests, Renovate pull requests, and commits pushed by
`ignazio-changelog[bot]`. It never uses `pull_request_target`, personal tokens,
force push, or broad staging. Only `CHANGELOG.md` is staged, and the staged path
is checked before commit.

Concurrent runs for the same pull request still cancel the older run as an
early optimization; correctness does not rely on cancellation because stale
branch writes are classified explicitly.

## Local verification

Install git-cliff 2.13.1, then run:

```bash
GIT_CLIFF=git-cliff scripts/test-changelog.sh
bash scripts/test-changelog-policy.sh
bash scripts/test-changelog-race.sh
```

The generation test covers tagged and untagged history, existing and missing
changelogs, idempotence, Conventional and unconventional commits, all required
groups, and exclusion of the bot changelog commit. The policy and race tests
cover bot exclusions, bounded retry wiring, a current fast-forward update, a
stale branch advance that must not write, and a real push rejection that must
remain fatal.
