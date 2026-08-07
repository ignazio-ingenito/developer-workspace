# Changelog automation

`developer-workspace` owns the reusable workflow at
`.github/workflows/changelog-reusable.yml`. Applicable repositories call it
from a minimal `pull_request` wrapper; they do not copy the git-cliff logic.

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

## Security behavior

The changelog job is skipped for forks, non-PR events, the repository default
branch, and commits pushed by `ignazio-changelog[bot]`. It never uses
`pull_request_target`, personal tokens, force push, or broad staging. Only
`CHANGELOG.md` is staged, and the staged path is checked before commit.

Concurrent runs for the same pull request cancel the older run. A normal
fast-forward push failure remains safe: the next `synchronize` event processes
the newer pull request head.

## Local verification

Install git-cliff 2.13.1, then run:

```bash
GIT_CLIFF=git-cliff scripts/test-changelog.sh
```

The test uses temporary repositories and covers tagged and untagged history,
existing and missing changelogs, idempotence, Conventional and unconventional
commits, all required groups, and exclusion of the bot changelog commit.
