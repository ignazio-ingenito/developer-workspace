# Task 9 — n8n Runtime Owner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Draft  
**Mission:** `ignazio-ingenito/developer-workspace#33` — Task 9

**Goal:** Determine the simplest deterministic Git→n8n runtime owner from the live entitlement, then write the selected owner's concrete implementation plan without preserving hidden live publication state by default.

**Architecture:** This tranche begins with a read-only runtime fact, not code. The current Homelab importer remains untouched until the license/Source Control entitlement is known. The decision tranche ends with one selected upstream owner (or one evidence-backed DEFER); any runtime mutation belongs to the follow-on implementation plan for that owner.

**Tech Stack:** n8n 2.32.7 as currently deployed, Kubernetes, Argo CD, n8n Server CLI/Public API/native Source Control as applicable.

## Global Constraints

- RFC-0001 v0.1.6 is authoritative.
- Active sources are `homelab/gitops/apps/n8n/deployment.yaml`, `homelab/gitops/apps/n8n-workflows/import-job.yaml`, `homelab/doc/28-n8n-workflow-gitops-importer.md`, and active `n8n-workflows` README/CONTEXT.
- Current deployment is one replica, `Recreate`, n8n `2.32.7`, PostgreSQL-backed.
- Current importer performs `export:workflow -> custom Node live-state intersection -> import:workflow -> publish:workflow` and does not restart n8n.
- Do not infer Source Control entitlement from repository history or old handoffs.
- Entitlement verification is read-only.
- Never expose raw license keys, API keys, encryption keys or database credentials in comments/plans.
- Do not add queue/multi-main merely to make `--activeState=fromJson` available.
- Do not preserve hidden live publication state merely because the current importer does so.
- Do not create a new API secret before the selected design proves it is required.
- Do not restart n8n as exploratory diagnosis.
- No GitHub Actions rerun.

---

### Task 1: Verify the live n8n license/Source Control entitlement read-only

**Files:**
- No repository changes.
- Update after verification: existing `developer-workspace#33` comment stream only.

**Interfaces:**
- Consumes: live `apps/n8n` Deployment.
- Produces: exactly one classification: `SOURCE_CONTROL_ENTITLED=yes`, `SOURCE_CONTROL_ENTITLED=no`, or `SOURCE_CONTROL_ENTITLED=indeterminate`.

- [ ] **Step 1: Confirm live image and pod before reading license state**

```bash
kubectl -n apps get deploy n8n -o jsonpath='{.spec.template.spec.containers[?(@.name=="n8n")].image}{"\n"}'
kubectl -n apps get pods -l app.kubernetes.io/name=n8n -o wide
```

Repository target is:

```text
harbor.lab.skunklabs.uk/docker-io/n8nio/n8n:2.32.7
```

If live differs, record the drift first; do not pretend Git and runtime are identical.

- [ ] **Step 2: Query installed license information**

```bash
kubectl -n apps exec deploy/n8n -- n8n license:info
```

Record only edition/entitlement/expiry facts needed for Source Control. Do not paste raw key/token material.

- [ ] **Step 3: Classify without inference**

Choose one literal value:

```text
SOURCE_CONTROL_ENTITLED=yes
SOURCE_CONTROL_ENTITLED=no
SOURCE_CONTROL_ENTITLED=indeterminate
```

Use `indeterminate` only if command/runtime access is unavailable or the output does not answer entitlement. Absence of Source Control configuration in Git is not evidence for `no`.

- [ ] **Step 4: Append a factual Wave #33 note**

The note contains only:

```text
n8n Task 9 entitlement reality check
live image: [the exact image string printed in Step 1]
command: kubectl -n apps exec deploy/n8n -- n8n license:info
classification: SOURCE_CONTROL_ENTITLED=yes|no|indeterminate using the one observed value
mutation/restart: none
```

When writing the actual comment, replace the bracketed instruction with the exact observed image and keep only the single observed classification value. No child Issue is created.

---

### Task 2A: For an entitled installation, test native Source Control against the required contract

**Files:**
- No runtime files changed.
- Modify after decision: `developer-workspace/docs/superpowers/specs/2026-08-14-task9-integration-runtime-design.md`.

**Interfaces:**
- Entry: observed classification is `SOURCE_CONTROL_ENTITLED=yes`.
- Produces: `N8N_OWNER=native-source-control` only if every contract line passes.

- [ ] **Step 1: Re-read current official n8n Source Control documentation**

Verify at execution time that native Source Control can support a one-way production pull, private repository use, explicit workflow promotion/publication semantics and rollback by Git revision without using production database state as source of truth.

- [ ] **Step 2: Apply the exact acceptance matrix**

Mark each line PASS or FAIL with official-source evidence:

```text
Git owns workflow definitions.
Production does not push workflow definitions back to Git.
A Git revision can be promoted deterministically to production.
Published/unpublished behavior is explicit and does not depend on pre-import hidden live state.
No queue/multi-main architecture is required solely for deployment.
Rollback can select a previous Git revision rather than reconstructing database state.
```

- [ ] **Step 3: Select native Source Control only on six PASS results**

If all six pass, record:

```text
N8N_OWNER=native-source-control
```

Then write a new focused implementation plan whose exact scope is: native repository/environment configuration, migration from current importer, rollback, retirement of importer manifest/test/custom Node state code after cutover proof, and `export-live.sh` recovery-only burden.

Do not mutate n8n during this decision task.

- [ ] **Step 4: On any FAIL, record the failed invariant and continue to Task 2B**

Entitlement alone is not a reason to choose the feature.

---

### Task 2B: For unavailable/insufficient Source Control, compare Public API ownership with Server CLI

**Files:**
- No runtime files changed.
- Modify after decision: `developer-workspace/docs/superpowers/specs/2026-08-14-task9-integration-runtime-design.md`.

**Interfaces:**
- Entry: classification is `no`/`indeterminate`, or Task 2A has a concrete FAIL.
- Produces: `N8N_OWNER=public-api`, `N8N_OWNER=native-source-control`, or `N8N_OWNER=defer:<concrete blocker>`.

- [ ] **Step 1: Re-read current official Server CLI and Public API/official API CLI documentation**

For both candidates record current support for create/update, publish/unpublish, authentication/scopes, workflow identity updates, running-instance effect without restart, and tooling stability status.

- [ ] **Step 2: Apply the existing Server CLI runtime caveat**

Current Active Homelab documentation already establishes that `publish:workflow` against the live DB does not refresh the running n8n process until restart, and non-multi-main imports can leave previous cron triggers loaded.

Therefore `export -> import -> publish` cannot be selected as deterministic owner unless current upstream behavior provides a native way to remove that caveat without adding new architecture.

- [ ] **Step 3: Apply the Public API acceptance matrix**

Mark PASS/FAIL for:

```text
Git workflow definition can create/update the intended workflow identity.
Desired published/unpublished state is explicit in Git/deployment policy.
The running instance receives the new definition/state without hidden pre-import live-state reconstruction.
Authentication can be least-privilege.
Partial update/publication fails closed and is observable.
Rollback can reapply the previous Git revision.
```

- [ ] **Step 4: Price any new API credential/tool explicitly**

If API ownership requires a key, the decision record must state its required scopes, SOPS ownership location, consuming workload and rotation/revocation consequence. Do not create the key yet.

If the official API CLI is beta, record that as recurring maintenance/stability cost.

- [ ] **Step 5: Emit exactly one owner result**

Allowed results:

```text
N8N_OWNER=public-api
N8N_OWNER=native-source-control
N8N_OWNER=defer:runtime-access-unavailable
N8N_OWNER=defer:required-upstream-capability-unavailable
```

Use a DEFER value only when its named blocker is actually observed. If `public-api` or `native-source-control` is selected, write that owner's focused implementation plan before any importer/secret mutation.

---

### Task 3: Reconcile the coordinator design with the observed fact and selected owner

**Files:**
- Modify: `developer-workspace/docs/superpowers/specs/2026-08-14-task9-integration-runtime-design.md`
- Update: existing `developer-workspace#33` comment stream.

**Interfaces:**
- Consumes: exact entitlement result, official capability matrix and selected owner.
- Produces: an Active coordinator design that distinguishes fact, decision and rejected alternative.

- [ ] **Step 1: Add four explicit statements to the coordinator design**

Write four normal prose bullets, populated with the actual observations from Tasks 1–2:

1. the exact live n8n image and entitlement classification;
2. the upstream capability that passed the selected matrix;
3. the selected owner and the RFC-0001 reason (simplicity, reliability, overhead, reversibility);
4. the strongest rejected alternative and the concrete invariant/cost that caused rejection.

Do not use generic labels such as “best practice” without the concrete comparison.

- [ ] **Step 2: Keep historical handoffs Archived**

Do not rewrite May/June handoffs. Runtime README/CONTEXT/runbook changes belong to the selected owner's follow-on implementation plan, after implementation exists.

- [ ] **Step 3: Preserve recovery vs steady-state ownership**

The follow-on plan may keep `export-live.sh` only as recovery/migration utility with a demonstrated consumer. It must not become a steady-state reverse synchronization path.

---

## Completion Gate

This decision tranche is complete when:

- live entitlement has one evidence-backed classification;
- one owner value or one concrete DEFER value is recorded;
- the coordinator Active design reflects the fact/decision split;
- no runtime mutation, restart, API-key creation or GitHub Actions retry occurred during decision work;
- an implementation owner has its own focused plan before runtime changes begin.

The n8n implementation tranche is complete later only when that focused plan removes hidden live-state reconstruction from steady state (or a valid external blocker remains documented), makes running-runtime semantics/rollback/first publication explicit, and aligns Active runtime docs.
