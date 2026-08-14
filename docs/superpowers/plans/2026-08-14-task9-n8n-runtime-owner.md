# Task 9 — n8n Runtime Owner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Draft  
**Mission:** `ignazio-ingenito/developer-workspace#33` — Task 9

**Goal:** Determine the simplest deterministic Git→n8n runtime owner from the live entitlement, then produce the exact implementation plan without preserving hidden live publication state by default.

**Architecture:** This tranche begins with a read-only runtime fact, not code. The current Homelab importer remains untouched until the license/Source Control entitlement is known. The result selects one native/upstream ownership path; only then is a concrete implementation plan allowed.

**Tech Stack:** n8n 2.32.7 as currently deployed, Kubernetes, Argo CD, n8n Server CLI/Public API/native Source Control as applicable.

## Global Constraints

- RFC-0001 v0.1.6 is authoritative.
- Active sources are `homelab/gitops/apps/n8n/deployment.yaml`, `homelab/gitops/apps/n8n-workflows/import-job.yaml`, `homelab/doc/28-n8n-workflow-gitops-importer.md`, and active `n8n-workflows` README/CONTEXT.
- Current deployment is single replica, `Recreate`, n8n `2.32.7`, PostgreSQL-backed.
- Current importer performs `export:workflow -> custom Node live-state intersection -> import:workflow -> publish:workflow` and does not restart n8n.
- Do not assume Source Control entitlement from repository history or old handoffs.
- The entitlement check must be read-only.
- Do not expose raw license keys, API keys, encryption keys or database credentials in comments/plans.
- Do not add queue/multi-main merely to make `--activeState=fromJson` available.
- Do not preserve hidden live publication state merely because the current importer does so.
- Do not create a new API secret before the selected design proves it is required.
- Do not restart n8n as an exploratory diagnostic step.
- No GitHub Actions rerun.

---

### Task 1: Verify the live n8n license/Source Control entitlement read-only

**Files:**
- No repository changes.

**Interfaces:**
- Consumes: live `apps/n8n` Deployment.
- Produces: one factual classification: `SOURCE_CONTROL_ENTITLED=yes|no|indeterminate` plus non-secret evidence.

- [ ] **Step 1: Confirm the live pod corresponds to the expected deployment before reading license state**

Run read-only:

```bash
kubectl -n apps get deploy n8n -o jsonpath='{.spec.template.spec.containers[?(@.name=="n8n")].image}{"\n"}'
kubectl -n apps get pods -l app.kubernetes.io/name=n8n -o wide
```

Expected repository target image:

```text
harbor.lab.skunklabs.uk/docker-io/n8nio/n8n:2.32.7
```

If live differs from Git, record the drift before using live licensing as a design fact.

- [ ] **Step 2: Query n8n license information inside the existing pod**

Run:

```bash
kubectl -n apps exec deploy/n8n -- n8n license:info
```

Do not copy any secret/license token into GitHub. Record only fields needed to determine edition/entitlement/expiry and whether Source Control is available.

- [ ] **Step 3: Classify the result**

Use exactly one classification:

```text
SOURCE_CONTROL_ENTITLED=yes
SOURCE_CONTROL_ENTITLED=no
SOURCE_CONTROL_ENTITLED=indeterminate
```

`indeterminate` is used only if the command is unavailable, output does not expose the necessary entitlement, or runtime access is blocked. Do not infer `no` from absence of repository configuration.

- [ ] **Step 4: Record the factual result on the existing Wave #33 context**

Add a concise comment to `developer-workspace#33` containing:

- exact live image;
- command used;
- entitlement classification;
- no secrets/raw key material;
- statement that no n8n mutation/restart occurred.

Do not open a child Issue merely for this fact.

---

### Task 2A: If Source Control is entitled, verify it covers the required one-way Git→production flow

**Files:**
- No runtime changes yet.
- Potential follow-on design file under `developer-workspace/docs/superpowers/specs/` only after the checks below.

**Interfaces:**
- Entry condition: `SOURCE_CONTROL_ENTITLED=yes`.
- Produces: `N8N_OWNER=native-source-control` only if all acceptance criteria pass.

- [ ] **Step 1: Re-read current official n8n Source Control documentation**

Verify from official n8n documentation at execution time:

- production can receive a one-way pull from Git;
- workflow definitions can be promoted without treating the production database as source of truth;
- publication/activation behavior is explicit enough to replace the hidden live-state preservation;
- required credentials and repository layout are compatible with the current private `n8n-workflows` repository.

Do not rely on the archived May/June handoffs.

- [ ] **Step 2: Compare native Source Control against current invariants**

The native path passes only if it can satisfy all of:

```text
Git owns workflow definitions.
Production does not push workflow definitions back to Git.
A deploy of a Git revision has deterministic publication semantics.
No custom Node state reconstruction remains.
No queue/multi-main architecture is introduced solely for deployment.
Rollback is a Git revision/pull operation, not a hidden database-state reconstruction.
```

- [ ] **Step 3: If all criteria pass, select the native owner**

Record:

```text
N8N_OWNER=native-source-control
```

Then create a focused follow-on implementation plan covering only:

- repository/environment configuration required by native Source Control;
- migration from current importer;
- exact rollback;
- retirement of importer manifest/test/custom live-state code after cutover proof;
- treatment of `export-live.sh` as recovery/migration-only if it still passes burden of proof.

Do not implement during this task before that plan is written/reviewed.

- [ ] **Step 4: If any criterion fails, do not force native Source Control**

Record the specific unsupported invariant and proceed to Task 2B. Entitlement alone is not sufficient reason to keep the feature.

---

### Task 2B: If Source Control is unavailable or insufficient, compare Public API ownership against the Server CLI

**Files:**
- No runtime changes yet.
- Potential follow-on design file under `developer-workspace/docs/superpowers/specs/` after the comparison.

**Interfaces:**
- Entry condition: `SOURCE_CONTROL_ENTITLED=no|indeterminate`, or Task 2A found a concrete capability gap.
- Produces: one selected upstream path or a justified DEFER.

- [ ] **Step 1: Re-read current official n8n Server CLI and Public API/official CLI documentation**

Verify at execution time:

- create/update workflow support;
- publish/unpublish support;
- authentication model and scopes;
- whether operations take effect in a running single-main instance without restart;
- stability status of any official API CLI used;
- behavior for workflow IDs and updates.

- [ ] **Step 2: Reject the current Server CLI sequence as owner unless its runtime-refresh caveat is solved natively**

The current Active runbook documents that `publish:workflow` against the live DB does not refresh the running n8n process until restart and that existing cron triggers can remain loaded after import on non-multi-main.

Therefore `export -> import -> publish` is not accepted as deterministic Git→runtime ownership merely because the commands succeed in the database.

- [ ] **Step 3: Evaluate a Public API path against the exact contract**

A Public API/official API CLI candidate passes only if it can:

```text
read a Git workflow definition;
create or update the intended workflow identity;
make desired published/unpublished state explicit from Git/deployment policy;
apply that state to the running instance without hidden pre-import live-state reconstruction;
use a least-privilege credential;
fail closed on partial update/publication failure;
allow rollback to the previous Git revision.
```

- [ ] **Step 4: Apply RFC burden to the API credential/tooling**

If the API path needs a new key, record:

- required scopes;
- where the SOPS-owned secret would live;
- which workload consumes it;
- rotation/revocation consequence.

Do not create the key during comparison.

If the official API CLI is beta, include that maintenance/stability cost in the comparison rather than hiding it.

- [ ] **Step 5: Select or defer**

Allowed outputs are:

```text
N8N_OWNER=public-api
N8N_OWNER=native-source-control
N8N_OWNER=defer:<concrete external blocker>
```

`defer` requires a real blocker such as unavailable entitlement/runtime access or a missing upstream capability. “Need more research” is not a sufficient blocker after Tasks 1–2B.

If `public-api` is selected, create a focused implementation plan before any importer/API-key mutation.

---

### Task 3: Reconcile Task 9 design and active documentation with the selected n8n owner

**Files:**
- Modify as applicable: `developer-workspace/docs/superpowers/specs/2026-08-14-task9-integration-runtime-design.md`
- Modify as applicable after implementation: `homelab/doc/28-n8n-workflow-gitops-importer.md`
- Modify as applicable after implementation: `n8n-workflows/README.md`
- Modify as applicable after implementation: `n8n-workflows/CONTEXT.md`

**Interfaces:**
- Consumes: factual entitlement and selected owner.
- Produces: no Active document that describes a superseded importer as target state.

- [ ] **Step 1: Record fact vs decision explicitly**

Use this form in the coordinator design:

```text
Fact: <license/entitlement result and live version>.
Fact: <upstream capability verified>.
Decision: <selected owner> because <specific RFC-0001 value/simplicity/reliability reason>.
Not selected: <alternative> because <concrete trade-off/failure>.
```

- [ ] **Step 2: Do not rewrite historical handoffs**

Archived n8n handoffs remain historical evidence. Only Active README/CONTEXT/runbook sources are changed to describe the resulting implementation.

- [ ] **Step 3: Preserve rollback and recovery distinction**

`export-live.sh` may remain only if it is clearly recovery/migration utility and still has a demonstrated consumer. It must not silently become the steady-state source-of-truth loop again.

---

## Completion Gate

The n8n tranche is complete when one of these is true:

**Implemented path:**
- live entitlement was verified read-only;
- one deterministic upstream Git→runtime owner was selected and implemented from its own reviewed plan;
- hidden live publication-state reconstruction is removed from steady state;
- running-runtime semantics, rollback and first-publication behavior are explicit;
- Active docs match the result.

**Valid DEFER:**
- live entitlement or a required upstream capability is objectively unavailable;
- the blocker is documented with evidence;
- no speculative custom replacement was added;
- current importer risk/caveat remains accurately documented as temporary state.

In both cases, no exploratory restart, secret creation or GitHub Actions retry is allowed without separate authorization/need.
