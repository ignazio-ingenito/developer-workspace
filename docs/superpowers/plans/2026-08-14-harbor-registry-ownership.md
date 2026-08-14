# Harbor Registry Ownership Implementation Plan

> **For agentic workers:** execute task-by-task; do not merge or perform destructive Harbor changes without explicit Product Owner authorization.

**Goal:** Replace custom Harbor REST reconciliation in `ignazio-ingenito/homelab` with the official `goharbor/harbor` OpenTofu provider for steady-state configuration, while deleting completed migration machinery and retaining only runtime checks that prove a distinct failure.

**Architecture:** Reuse the existing `infra/opentofu` pattern in Homelab. Adopt existing Harbor objects into provider state before any apply; require a non-destructive plan. Configuration ownership moves to provider resources. Historical cutover/retirement jobs do not become provider resources: if already completed, delete them. Runtime pull smoke remains separate from configuration ownership and survives only if it proves a cluster pull/auth/cache failure not covered by normal workloads.

**Tech Stack:** OpenTofu >=1.6, official `goharbor/harbor` provider, Harbor API, GitHub Actions, ArgoCD/Kustomize.

## Global Constraints

- Wave #33 burden of proof: DELETE is default for custom code and tests.
- No custom wrapper around OpenTofu/provider.
- No destructive Harbor operation, resource replacement, state removal, merge, or PR close without explicit Product Owner authorization.
- Existing Harbor objects must be imported/adopted before apply.
- First accepted plan must contain no destroy/recreate for steady-state Harbor resources.
- Do not create HCL shape/string contract tests. Use provider validation/plan as the authoritative configuration test.
- Keep runtime smoke only for a concrete runtime failure distinct from provider configuration validation.

---

### Task 1: Inventory and classify current Harbor automation

**Repository:** `ignazio-ingenito/homelab`

**Classify:**
- `gitops/infra/harbor-config/private-ghcr-replication.yaml`: steady-state reconciler + runtime canonical smoke. Split responsibilities; provider owns configuration, smoke reviewed separately.
- `private-ghcr-calver-immutability.yaml` and `private-ghcr-baialupo-calver-immutability.yaml`: steady-state immutability policy -> provider.
- `private-ghcr-proxy-retirement.yaml`: historical one-shot retirement + cache-miss smoke -> delete retirement machinery if live state confirms completion; review smoke independently.
- `private-ghcr-legacy-immutability-retirement.yaml`: historical one-shot cleanup -> delete if live state confirms completion.
- `harbor-n8n-webhook-auth.enc.yaml`: keep only if webhook remains an approved Task 6/7 consumer; provider may consume the secret, not duplicate it.
- `.github/workflows/harbor-config-contract.yml`: replace custom Python/config contracts with provider-native validation/plan and the minimum relevant security scan.
- Harbor/private-GHCR Python tests that execute embedded reconciler code or assert YAML strings: DELETE with the custom mechanism.

**Verification:** record classification on the Task 6 PR, not in a new inventory document.

### Task 2: Create native Harbor OpenTofu root

**Files in Homelab:**
- Create `infra/opentofu/harbor/main.tf`
- Create `infra/opentofu/harbor/variables.tf`
- Create `infra/opentofu/harbor/outputs.tf` only if an output has an actual consumer; otherwise omit.
- Reuse existing repository conventions for provider versioning/state; do not create a module layer.

**Provider:** `goharbor/harbor` pinned to a compatible current minor after checking the provider release used during implementation.

**Steady-state resources to model where supported:**
- canonical/private proxy-cache project(s);
- registry endpoint for authenticated GHCR;
- project metadata/scan policy;
- pull robot permissions;
- retention policies;
- garbage collection schedule;
- scan-all schedule/config if supported by the provider version;
- scan webhook policies if still required;
- CalVer immutable tag rules for `developer-workspace` and `baialupo.com`;
- replication only if a steady-state replication policy still exists after the completed proxy-cache cutover. Do not recreate retired replication merely because the old reconciler contains code for it.

**Verification:** `tofu fmt -check`, `tofu init -backend=false`, `tofu validate`. No custom HCL contract test.

### Task 3: Adopt live Harbor objects without mutation

**Action:** determine exact import IDs from live Harbor/provider docs and import all existing steady-state objects into an isolated Task 6 state/workspace.

**Safety gate:** run `tofu plan` after import. Acceptable first plan is no-op or in-place convergence of explicitly intended attributes. Any destroy/recreate, project deletion, robot recreation/secret rotation, registry endpoint replacement, or other destructive change is a STOP requiring Product Owner decision.

**Do not apply yet.**

### Task 4: Remove steady-state custom reconciler and its tests

**After Task 3 has a safe plan:**
- Remove embedded steady-state Python from `private-ghcr-replication.yaml` and provider-owned Jobs/ConfigMaps.
- Remove `private-ghcr-calver-immutability.yaml` and `private-ghcr-baialupo-calver-immutability.yaml` after their live rules are provider-owned.
- Remove tests that exist only to validate these scripts, including current webhook reconciler, CalVer reconciler, robot reconciliation, and YAML-shape/DNS contracts when they have no distinct runtime failure.
- Remove matching references from `.github/workflows/harbor-config-contract.yml` and `kustomization.yaml`.

**Verification:** render remaining Kustomize, `tofu validate`, safe `tofu plan`, relevant Trivy config scan. Do not add replacement shape tests.

### Task 5: Retire completed one-shot migration machinery

**Files:**
- `private-ghcr-proxy-retirement.yaml`
- `private-ghcr-legacy-immutability-retirement.yaml`
- associated retirement-only tests and kustomization patches.

**Precondition:** read-only live checks confirm canonical proxy-cache exists, temporary project is absent, old replication is absent, and legacy immutability cleanup no longer has work.

**Decision:** if precondition holds, DELETE files/tests. Do not migrate one-shot cleanup logic into OpenTofu. If cleanup is incomplete, stop before deletion and report only the remaining one-time operation; executing destructive cleanup requires explicit Product Owner authorization.

### Task 6: Re-audit runtime Harbor smoke

**Candidate KEEP:** actual cluster-side authenticated pull of a known image through Harbor that verifies a real manifest/blob retrieval.

**Burden:** keep only if removing it would allow a concrete Harbor auth/proxy/cache regression to pass provider validation and normal deployment checks unnoticed. Exact historical tag/digest and hand-written Registry API protocol are not sacred.

**Preferred simplification:** if a minimal `crictl`/container runtime/image-pull Job using the existing `harbor-pull` secret proves the same failure with less custom code, use that standard runtime path. If normal ArgoCD workloads already provide equivalent reliable evidence, DELETE the dedicated smoke entirely.

### Task 7: Simplify Harbor CI ownership

**Workflow:** `.github/workflows/harbor-config-contract.yml`

Target responsibilities only:
- OpenTofu fmt/init/validate and non-destructive plan where credentials/state are safely available;
- Kustomize render only for remaining Kubernetes manifests;
- Trivy config/security checks only where they cover a distinct security failure.

DELETE:
- embedded reconciler unit contracts;
- YAML string/topology tests;
- `scripts/verify.sh` invocation if it only duplicates these checks (Task 11 owns broader verify/evidence review; coordinate rather than duplicate).

### Task 8: Exact-head verification and operational handoff

Before claiming Task 6 implementation complete:
- all retained CI checks green on exact head;
- OpenTofu plan shows no unintended destructive action;
- custom Harbor steady-state reconciler is absent;
- completed retirement machinery is absent or explicitly blocked by a live incomplete retirement;
- each retained Harbor test/smoke has a documented concrete failure story;
- no merge, apply, state deletion, or destructive live Harbor action performed without explicit authorization.

Progress denominator for implementation PR: 8 principal tasks; update only when a task is actually complete.
