# OCI Producer Standardization Design

Status: proposed for Wave #33 Task 5 implementation

## Context

Six repositories currently implement overlapping OCI build, scan, and publish
pipelines:

- `aeris`;
- `iwant`;
- `club-aviazione-popolare`;
- `prosignal`;
- `baialupo.com`;
- `skunklabs`.

The pipelines already aim to build once, scan the resulting image, and publish
the same bits. Several of them preserve that property with three jobs, Docker
tar artifacts, hand-written `commit-sha` and `image-ref` sidecars, repeated
label checks, per-tag push loops, digest parsers, workflow-shape tests, and
unconsumed reports or summaries. That glue is now a larger maintenance surface
than the invariant it protects.

Task 5 keeps the actual supply-chain properties and removes the accidental
protocol. The design follows current Docker and GitHub Actions capabilities:
job-level least privilege, immutable workflow artifacts where a privilege
boundary is real, Docker Buildx for the single build, Docker CLI for promotion
of the already-built image, and Trivy for the vulnerability gate.

Upstream basis:

- [docker/build-push-action inputs and outputs](https://github.com/docker/build-push-action/blob/master/_autodocs/04-action-io-reference.md);
- [GitHub Actions workflow permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax);
- [GitHub Actions data sharing between jobs](https://docs.github.com/en/actions/tutorials/store-and-share-data);
- [upload-artifact immutable artifact behavior](https://github.com/actions/upload-artifact/blob/main/docs/MIGRATION.md).

## Decision

Use a hybrid architecture based on the workflow trust boundary.

1. Trusted-only producers use one build, scan, and publish job.
2. Producers that also run for pull requests use an unprivileged
   `build-scan` job and a separate privileged `publish` job.
3. Multi-image repositories use a matrix instead of duplicated job families.
4. Every repository owns its small workflow directly. No central reusable
   workflow or replacement framework is introduced.

This is intentionally not a uniform topology. Job separation is retained only
where it prevents pull-request-controlled code from sharing a job token with
`packages: write`.

## Goals

- Build each image exactly once per workflow run.
- Run runtime checks and Trivy against that exact local image.
- Publish the same local image without a second BuildKit build.
- Keep `packages: write` out of pull-request build and scan jobs.
- Preserve existing image names, tags, runner classes, trigger paths, cache
  behavior, vulnerability thresholds, and first-attempt publication rules.
- Remove custom evidence and validators that have no independent consumer.
- Reduce duplicated YAML and shell while keeping repository-specific behavior
  local.

## Non-goals

- Moving any job between self-hosted and GitHub-hosted runners.
- Changing Harbor, GHCR, deployment manifests, image consumers, or Renovate.
- Redesigning Trivy ownership across producer, Harbor, and Homelab; that is
  Task 7.
- Adding signing, SBOM, provenance attestations, or a new evidence store.
- Introducing a reusable cross-repository workflow.
- Changing application builds, runtime behavior, image contents, or release
  notes.

## Trust classification

### Trusted-only workflows

`aeris`, `iwant`, and `skunklabs` build images only for trusted
`push`, tag, or manual events. Their image jobs may hold
`packages: write` because they do not execute pull-request code.

They use one job per image:

1. check out the trusted revision;
2. generate Docker metadata;
3. build once with `docker/build-push-action` and `load: true`;
4. run runtime checks where they already exist;
5. scan the loaded image with Trivy;
6. log in to GHCR;
7. apply the metadata tags to the loaded image;
8. publish all repository tags with Docker CLI.

### Pull-request-capable workflows

`club-aviazione-popolare`, `prosignal`, and `baialupo.com` also build
pull-request code. Their first job has only `contents: read` and never logs in
to a registry.

For a pull request, the job stops after build, runtime verification, and scan.
For a trusted publish event, it saves the already-scanned local image to one
Docker tar archive and uploads it as an immutable workflow artifact. The
artifact name includes repository-specific image identity,
`github.sha`, `github.run_id`, and `github.run_attempt`; retention is one
day and compression is disabled for the already-packed tar.

The dependent `publish` job:

1. runs only for the existing trusted publish conditions and first attempt;
2. has `contents: read` and `packages: write`;
3. downloads the artifact produced in the same run;
4. loads the image without rebuilding;
5. generates the existing publication tags;
6. logs in and pushes the loaded image.

`needs`, unique artifact naming, and artifact immutability replace the custom
`commit-sha` and `image-ref` files. The archive itself is the interface.

## Same-bits contract

Each build has one canonical local tag such as
`local/<repository-component>:sha-${{ github.sha }}`.

- Buildx loads that image into Docker exactly once.
- Runtime checks and Trivy address the canonical local tag.
- Trusted-only workflows tag and push that same local image.
- Pull-request-capable workflows save that local image after a successful scan;
  the publish job loads, tags, and pushes it.

No publish job invokes Buildx. No workflow rebuilds after scanning. There is no
separate SHA sidecar, label-verification protocol, or parsed digest equality
loop.

The metadata action remains the owner of tag generation. A minimal loop applies
and pushes its explicit multiline tag output. The loop relies only on Docker's
exit status; it does not capture, parse, compare, or summarize push responses.
Explicit tags are safer than `docker image push --all-tags` on persistent
self-hosted Docker daemons, where unrelated stale tags may exist locally.

## Repository changes

### Aeris

- Collapse `app`, `image-security`, and `publish` into one trusted image
  job on `ci-container`.
- Preserve main, version-tag, and manual triggers and current tag policy.
- Delete `scripts/ci/authorize-image-publish.sh`; the workflow trigger,
  job condition, and first-attempt condition own publication authorization.
- Remove only the matching topology and authorization assertions from
  `scripts/ci/test-release-workflow.sh`. Its unrelated quality and runtime
  checks remain.

### iWant

- Replace the duplicated application and migrator job families with one trusted
  matrix on `ci-container`.
- Matrix data owns Docker target, canonical local tag, registry image name, and
  human-readable component name.
- Preserve path filters, caches, tag policy, Trivy policy, and image names.
- Remove image sidecars, security-report artifacts, repeated load checks, and
  per-tag push loops.

### Skunklabs

- Keep the trusted single image job and release job on their current runner.
- Move permissions to the narrowest job scope.
- Keep the two Trivy severities and release-note behavior.
- Replace the custom push-output, manifest-inspection, digest comparison, and
  provenance-summary block with publication of the already-scanned local
  image.

### Club Aviazione Popolare

- Replace duplicated web and CMS build/scan/publish job families with a
  two-stage matrix: unprivileged `build-scan`, then privileged `publish`.
- Matrix data owns context, Dockerfile, local tag, registry image name, build
  arguments, and component label.
- Keep pull-request scanning, web/CMS image names, Directus build behavior,
  tag rules, and existing runner class.
- Remove sidecars, security-report artifacts, digest parsers, provenance
  summaries, and YAML-topology assertions.
- Retain the Dockerfile hardening and updater-ownership assertions currently
  colocated in `tests/test_supply_chain_workflow.py`, moving or renaming them
  so they no longer describe workflow topology.
- Delete `.github/workflows/retag-corrected-images.yml`; it is a completed
  one-time migration and has no steady-state responsibility.

### Prosignal

- Collapse build and scan into one unprivileged job; retain the privileged
  publish job for trusted events.
- Keep the synthetic characterization unit test, pull-request gate, image name,
  tag policy, and Trivy threshold.
- Delete `tests/test_supply_chain_workflow.py` and remove it from workflow
  paths and commands because it asserts the current YAML protocol rather than
  image behavior.
- Remove sidecars, the Trivy JSON artifact, manual digest extraction, and the
  workflow summary.

### Baialupo

- Split the current pull-request-capable job into unprivileged
  `build-scan` and privileged `publish` jobs on the existing runner class.
- Keep release-time changelog generation, Astro build, NGINX configuration
  validation, health smoke test, site URL inputs, cache, Trivy policies, and
  publication tags.
- Move `packages: write` from workflow scope to the publish job.
- Remove push-output digest parsing and the unconsumed image summary.

## Failure behavior

- Build, runtime verification, or blocking Trivy findings prevent artifact
  creation and publication.
- Pull-request runs never execute registry login or receive
  `packages: write`.
- Repositories that currently restrict publication by run attempt preserve
  their exact rule. This task does not invent a new rerun policy for producers
  that do not currently have one.
- A missing or invalid artifact causes the publish job to fail before login or
  push.
- Tagging or pushing any image failure fails the job; no parser is needed to
  reinterpret Docker's exit status.
- In pull-request-capable multi-image workflows, any failed build-scan matrix
  entry blocks publication of the image set and remains visible as a distinct
  component result. This avoids a partially published release.

## Evidence policy

Console logs, GitHub check conclusions, the immutable workflow artifact where
used, and the registry image are sufficient evidence for this task.

JSON Trivy reports, hand-written provenance summaries, digest comparison loops,
and workflow-shape tests have no current consumer or independent decision and
are deleted.

Native SBOM or provenance attestations are not added in this task. They would
require a named consumer and policy before their recurring cost is justified.
If such a requirement appears later, BuildKit or GitHub artifact attestations
must be used instead of restoring custom summaries.

## Verification

Each repository is changed and integrated independently.

1. Parse the changed workflow with a YAML-aware tool.
2. Run the repository's remaining canonical tests and linters.
3. Run action pin validation where it already exists.
4. Confirm no publish job contains `docker/build-push-action`.
5. Confirm pull-request jobs have no `packages: write` or registry login.
6. Confirm no removed sidecar, digest parser, evidence summary, or topology
   assertion remains.
7. Let the natural pull-request checks execute on the existing runner class.
8. After an authorized merge, observe the first trusted producer run and verify
   the expected image tags in GHCR before proceeding to the next repository.

No check is moved to a GitHub-hosted runner as part of validation.

## Rollout order

Use small repository-owned pull requests and verify one pattern before copying
it:

1. Aeris: trusted single-image pilot and removal of the redundant authorization
   wrapper.
2. Skunklabs: trusted single-image simplification.
3. Baialupo: pull-request boundary pilot with runtime smoke retained.
4. Prosignal: single-image two-stage producer.
5. iWant: trusted two-image matrix.
6. Club Aviazione Popolare: pull-request two-image matrix and retirement
   workflow deletion.

The rollout pauses after any producer fails its natural checks or its first
authorized post-merge publication. A failure is fixed in that repository
before the pattern advances.

## Alternatives rejected

### Uniform two-job pipeline

Keeping an artifact boundary in every repository gives one topology but retains
upload/download overhead where all inputs are already trusted. Uniform shape is
not sufficient value.

### Minimal edits to the current topology

Deleting only sidecars and digest parsing would leave duplicated job families,
repeated archive handling, and workflow-shape tests. It would not meet the
Wave's reduction target.

### Central reusable workflow

A central producer could reduce YAML repetition but would create a new
cross-repository contract, versioning problem, permission interface, and test
surface. Wave #33 explicitly avoids replacing deleted custom automation with a
new internal framework.

## Success criteria

- Every image is built once, checked, scanned, and published without rebuild.
- Pull-request jobs never receive registry write permission.
- Existing runners, triggers, image names, tags, caches, runtime checks, and
  blocking vulnerability thresholds remain intact.
- No custom commit sidecar, image-ref sidecar, digest parser, provenance
  summary, release authorization wrapper, or YAML topology test remains in the
  Task 5 surface.
- CAP's completed retag workflow is absent.
- Natural CI passes and each authorized trusted publication produces the
  expected GHCR tags.
- The aggregate Task 5 diff removes more pipeline code and test surface than it
  adds.
