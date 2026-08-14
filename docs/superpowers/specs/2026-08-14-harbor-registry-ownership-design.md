# Harbor Registry Ownership Design

Status: proposed for Wave #33 Task 6 implementation

## Context

Harbor steady-state configuration is currently reconciled from Homelab through a large Python script embedded in `gitops/infra/harbor-config/private-ghcr-replication.yaml`. The script calls Harbor REST API directly and owns projects, registry endpoints, robot permissions, retention, garbage collection, scan schedule, webhook policy, and legacy replication/cutover behavior.

This mixes three different responsibilities:

1. desired Harbor configuration;
2. one-shot migration/retirement procedures;
3. runtime verification of the resulting registry path.

Under Wave #33 burden of proof, the custom REST reconciler starts as `DELETE` candidate. A replacement is justified only if a standard owner covers the same steady-state responsibilities with less maintenance surface.

## Upstream sanity check

The official `goharbor/harbor` Terraform/OpenTofu provider covers the steady-state Harbor resource classes used here, including project, registry endpoint, replication, retention policy, robot account, webhook, immutable tag rule, garbage collection and system configuration.

Decision: use the official Harbor provider as the target owner for steady-state registry configuration. Do not introduce a wrapper or internal framework around it.

## Decision

### 1. Steady-state configuration → official Harbor provider

Move declarative Harbor state from the Python reconciler to OpenTofu/Terraform resources using the official Harbor provider.

Target ownership includes, where currently required:

- Harbor project configuration;
- external/private GHCR registry endpoint;
- proxy-cache project association;
- robot pull permissions;
- retention policies;
- garbage-collection schedule;
- scan-all schedule/system configuration where provider support is sufficient;
- project webhook policies;
- immutable tag rules;
- replication policy only where a steady-state policy is still required.

The provider configuration itself becomes the source of truth. Do not retain Python verification code that re-reads the same fields after apply.

### 2. Custom REST reconciler → DELETE

Delete the steady-state reconciliation path once equivalent provider resources are proven on the real Harbor instance.

This includes:

- embedded `reconcile.py`;
- Harbor API request/retry/comparison helpers;
- manual idempotency logic;
- exact-state post-write verification already owned by provider refresh/state;
- tests whose only purpose is to verify that reconciler implementation or YAML shape.

No replacement custom validator is introduced.

### 3. One-shot retirement/cutover → separate from steady state

Legacy project deletion, repository purge, legacy replication retirement, proxy migration and similar destructive transitions are not normal desired-state reconciliation.

They must not become permanent provider resources or automatic recurring jobs merely to preserve historical migration logic.

For each remaining one-shot operation:

- first determine whether it is already complete;
- if complete, DELETE its job/config/test residue;
- if still required, keep it as an explicit finite migration with a concrete stop condition;
- destructive execution requires explicit user authorization;
- after successful migration, delete the migration mechanism instead of keeping it in steady state.

### 4. Runtime smoke → independent burden of proof

The canonical private-GHCR pull smoke is not configuration ownership. It exercises real registry authentication, token exchange, manifest/blob pull and digest stability.

It is therefore evaluated independently from the provider migration.

Default remains DELETE, but it may survive only if it demonstrates a failure not sufficiently covered by provider apply, Harbor health, producer CI or cluster image pulls. If retained, it must be reduced to the smallest real runtime failure story and must not contain historical migration assertions.

### 5. Tests → DELETE by default

Current Harbor tests are reclassified by behavior rather than file history.

Strong DELETE candidates:

- reconciler implementation contracts;
- exact YAML/ConfigMap shape tests;
- migration/retirement tests for already-completed transitions;
- tests duplicating provider schema/state validation;
- exact policy-string tests where Harbor/provider is the natural owner.

Potential KEEP candidates require a concrete runtime/security failure story, e.g. a pull credential boundary or real registry path smoke not exercised elsewhere.

No provider-shape tests will be added.

## Architecture

Target steady state:

`OpenTofu/Terraform + official goharbor/harbor provider → Harbor API`

rather than:

`Argo CD Job → Python reconciler → Harbor REST API`

Argo CD may continue to own Kubernetes resources required to run Harbor or consumers, but it should not be used as a generic Harbor configuration reconciler when the provider is the domain owner.

## Secrets

Do not move clear-text Harbor/GHCR credentials into repository state.

Implementation must reuse existing encrypted/secret delivery mechanisms or another already-approved secret source. Provider credentials and sensitive registry credentials must be marked/handled as sensitive and must not be committed in plain text.

No new secret-management framework is introduced in Task 6.

## State and adoption

Existing Harbor objects must be adopted without destructive recreation where possible.

Implementation sequence:

1. declare provider resources for existing steady-state objects;
2. import/adopt existing Harbor objects into state where supported;
3. run plan and require no unintended destructive changes;
4. apply only after the migration plan is understood and authorized;
5. verify the real Harbor behavior;
6. then remove the equivalent Python reconciler and redundant tests.

Any provider limitation that would force unsafe recreation is a blocker to that specific resource, not justification to retain the entire reconciler.

## Non-goals

- changing Harbor deployment topology;
- changing registry naming without need;
- redesigning Trivy ownership (Task 7);
- replacing Argo CD generally;
- introducing a central CI framework;
- running destructive cutovers automatically;
- adding policy/evidence layers around OpenTofu/provider state.

## Verification

Task 6 implementation is successful when:

- every steady-state Harbor property has one authoritative owner;
- official provider resources cover all supported steady-state configuration;
- no duplicate Python REST reconciliation remains for provider-owned properties;
- provider plan is free of unintended destructive operations;
- required runtime behavior still works;
- completed migration/retirement residue is removed;
- surviving tests each demonstrate a distinct real failure;
- no new custom wrapper/validator is introduced.

## Rollout

1. Inventory current Harbor desired state and classify each reconciler responsibility as provider-owned, one-shot migration, runtime smoke or DELETE.
2. Add the minimal provider configuration and imports for steady-state resources.
3. Validate plan against the live Harbor state.
4. Migrate one resource group at a time only where the plan is non-destructive.
5. Remove matching reconciler code/tests immediately after ownership moves.
6. Retire completed one-shot jobs and migration tests.
7. Re-audit the remaining runtime smoke under the test burden.

No merge or destructive Harbor operation is part of this design PR.
