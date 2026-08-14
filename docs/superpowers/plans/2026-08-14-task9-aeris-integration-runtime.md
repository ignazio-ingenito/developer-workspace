# Task 9 — Aeris Integration Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Draft  
**Mission:** `ignazio-ingenito/developer-workspace#33` — Task 9  
**Target PR:** `ignazio-ingenito/aeris#248`

**Goal:** Keep the real historical-upgrade/RLS regression test while replacing the Testcontainers pilot with the simpler native GitHub Actions PostgreSQL service and removing the Testcontainers dependency.

**Architecture:** `Controlled Runtime` remains the single integration workflow. GitHub Actions owns PostgreSQL lifecycle and readiness; the Node test owns schema bootstrap, migration application, seed data and RLS assertions through `pg`. The test receives one database URL and knows nothing about Docker/container identity.

**Tech Stack:** GitHub Actions `services`, PostgreSQL 16 Alpine, Node.js 24, `pg`, pnpm 10.33.2.

## Global Constraints

- RFC-0001 v0.1.6 is authoritative.
- Work on existing PR `aeris#248`; do not open a second Aeris Task 9 PR.
- Preserve the four real assertions: linked aircraft access/edit allowed; unrelated aircraft access/edit denied.
- Preserve the historical-upgrade scenario that omits `009_rls_policies.sql` and then applies `009_pilot_aircraft_access.sql`.
- Keep exactly one integration workflow: `.github/workflows/controlled-runtime.yml`.
- Do not reintroduce `scripts/test-pilot-aircraft-access.sh`, `runtime-migrations.yml`, a `psql` wrapper, Docker discovery, fixed-port parsing, static YAML/shell shape tests or evidence artifacts.
- Do not keep `@testcontainers/postgresql` in steady state.
- PostgreSQL authentication must use an explicit password; do not use `POSTGRES_HOST_AUTH_METHOD=trust`.
- No GitHub Actions rerun. A new commit may produce a natural run; inspect that run only.
- Do not mix dependency upgrades unrelated to removing Testcontainers.

---

### Task 1: Make the integration test consume an external PostgreSQL URL

**Files:**
- Modify: `tests/integration/pilot-aircraft-access.test.mjs`

**Interfaces:**
- Consumes: environment variable `AERIS_INTEGRATION_DATABASE_URL` containing a fresh PostgreSQL database connection URI.
- Produces: one Node test that connects with `pg.Client` and leaves lifecycle ownership outside the test.

- [ ] **Step 1: Change the test boundary first so the missing workflow contract fails visibly**

Replace the Testcontainers import/startup with a required connection string:

```js
import assert from 'node:assert/strict'
import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'
import test from 'node:test'

import pg from 'pg'

const { Client } = pg
const repositoryRoot = process.cwd()

function integrationDatabaseURL() {
  const value = process.env.AERIS_INTEGRATION_DATABASE_URL
  assert.ok(value, 'AERIS_INTEGRATION_DATABASE_URL is required')
  return value
}
```

Inside the test body replace:

```js
const container = await new PostgreSqlContainer('postgres:16-alpine').start()
const client = new Client({ connectionString: container.getConnectionUri() })
```

with:

```js
const client = new Client({ connectionString: integrationDatabaseURL() })
```

and replace the existing `finally` block with:

```js
} finally {
  await client.end().catch(() => undefined)
}
```

Do not change the SQL scenario or the domain assertions.

- [ ] **Step 2: Run the test without the workflow service to verify the new interface fails closed**

Run:

```bash
pnpm test:integration
```

Expected: FAIL with `AERIS_INTEGRATION_DATABASE_URL is required`.

This failure is intentional and proves the test no longer creates hidden infrastructure itself.

- [ ] **Step 3: Review the diff to ensure only lifecycle code changed**

Run:

```bash
git diff -- tests/integration/pilot-aircraft-access.test.mjs
```

Expected: removal of `@testcontainers/postgresql`, container start/stop and nothing in the historical-upgrade/RLS assertions.

---

### Task 2: Give `Controlled Runtime` a native PostgreSQL service

**Files:**
- Modify: `.github/workflows/controlled-runtime.yml`

**Interfaces:**
- Consumes: GitHub Actions service-container capability on `ci-container`.
- Produces: `AERIS_INTEGRATION_DATABASE_URL=postgres://postgres:aeris-integration@127.0.0.1:5432/aeris_integration` for the Node test.

- [ ] **Step 1: Add the native service with password authentication and health check**

Under `jobs.controlled-runtime`, add:

```yaml
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: aeris-integration
          POSTGRES_DB: aeris_integration
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U postgres -d aeris_integration"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 12
```

Replace the current job environment:

```yaml
    env:
      DOCKER_HOST: unix:///var/run/docker.sock
```

with:

```yaml
    env:
      AERIS_INTEGRATION_DATABASE_URL: postgres://postgres:aeris-integration@127.0.0.1:5432/aeris_integration
```

No step in the resulting job should call Docker directly.

- [ ] **Step 2: Keep the execution step minimal**

The final execution step remains exactly:

```yaml
      - name: Verify PostgreSQL-backed controlled runtime
        run: pnpm test:integration
```

Do not add `psql`, Docker inspection or readiness loops; GitHub owns service readiness.

- [ ] **Step 3: Verify the workflow no longer contains the retired orchestration vocabulary**

Run:

```bash
for token in POSTGRES_HOST_AUTH_METHOD POSTGRES_SERVICE_CONTAINER_ID 'docker exec' 'docker ps' '@testcontainers'; do
  ! grep -F "$token" .github/workflows/controlled-runtime.yml
done
```

Expected: PASS.

---

### Task 3: Remove the Testcontainers dependency cleanly

**Files:**
- Modify: `package.json`
- Modify: `pnpm-lock.yaml`

**Interfaces:**
- Consumes: the test no longer imports `@testcontainers/postgresql`.
- Produces: dependency graph without Node Testcontainers.

- [ ] **Step 1: Remove only the Testcontainers package**

Run:

```bash
pnpm remove -D @testcontainers/postgresql
```

Expected: `package.json` and `pnpm-lock.yaml` change; unrelated package versions do not move.

- [ ] **Step 2: Verify a frozen install succeeds**

Run:

```bash
pnpm install --frozen-lockfile
```

Expected: PASS.

- [ ] **Step 3: Verify no Testcontainers dependency remains**

Run:

```bash
! grep -R "@testcontainers/postgresql\|testcontainers@" package.json pnpm-lock.yaml tests/integration .github/workflows/controlled-runtime.yml
```

Expected: PASS.

- [ ] **Step 4: Commit the functional Aeris change**

```bash
git add .github/workflows/controlled-runtime.yml tests/integration/pilot-aircraft-access.test.mjs package.json pnpm-lock.yaml
git commit -m "test: use native PostgreSQL service for controlled runtime"
```

---

### Task 4: Verify the current head without CI retries

**Files:**
- No new files.

**Interfaces:**
- Consumes: exact PR head produced by Task 3.
- Produces: evidence that the native service and the retained RLS test work on `ci-container`.

- [ ] **Step 1: Run cheap local checks that do not need PostgreSQL**

Run:

```bash
pnpm install --frozen-lockfile
pnpm test
```

Expected: PASS.

- [ ] **Step 2: Push the new commit to the existing `aeris#248` branch**

Push the existing branch normally. Do not invoke `workflow_dispatch` and do not rerun any existing run.

- [ ] **Step 3: Inspect the natural `Controlled Runtime` run for the exact new head**

Acceptance:

- checkout step started normally;
- PostgreSQL service became healthy;
- `pnpm test:integration` PASS;
- no wrapper/Docker discovery step exists;
- no manual rerun was used.

If a run has zero steps or fails before the first step, classify it as infrastructure and stop; do not retry.

- [ ] **Step 4: If the integration assertion fails, diagnose from the existing logs before changing code**

Classify the failure as one of:

- connection/service setup;
- historical bootstrap/migration;
- seed data;
- linked-aircraft authorization;
- unrelated-aircraft denial.

Do not add generic retries, sleeps or wrapper code to mask the failure.

---

### Task 5: Reconcile Aeris Active documentation and PR metadata

**Files:**
- Modify: `README.md`
- Modify: `docs/current-state.md`
- Update: PR `aeris#248` body

**Interfaces:**
- Consumes: verified final runtime design from Task 4.
- Produces: Active docs that describe GitHub service PostgreSQL + Node/`pg`, not Testcontainers.

- [ ] **Step 1: Replace premature Testcontainers steady-state claims**

Document the resulting contract as:

```text
Controlled Runtime is the single PostgreSQL/RLS integration owner.
GitHub Actions starts a password-authenticated postgres:16-alpine service.
The Node integration test connects through AERIS_INTEGRATION_DATABASE_URL,
replays the historical-upgrade scenario and verifies linked/unrelated aircraft authorization.
No custom psql wrapper, Docker discovery script, Runtime Migrations workflow or Testcontainers dependency is part of the steady state.
```

Do not reintroduce deleted historical implementation detail.

- [ ] **Step 2: Update PR #248 to state the final decision rather than the pilot decision**

The PR body must distinguish:

- **fact:** Testcontainers pilot proved the test could leave Bash;
- **decision:** native GitHub service is simpler for the final single-Postgres Aeris case;
- **result:** Testcontainers removed, real RLS contract retained.

- [ ] **Step 3: Verify documentation and code agree**

Run:

```bash
! grep -R "@testcontainers/postgresql\|Testcontainers" README.md docs/current-state.md package.json .github/workflows/controlled-runtime.yml tests/integration/pilot-aircraft-access.test.mjs
```

Expected: PASS unless a historical paragraph explicitly labels the pilot as historical evidence. If such a paragraph exists, it must not describe the active architecture.

- [ ] **Step 4: Commit documentation reconciliation**

```bash
git add README.md docs/current-state.md
git commit -m "docs: align Aeris controlled runtime ownership"
```

---

## Completion Gate

Aeris Task 9 tranche is ready when all are true:

- one `Controlled Runtime` workflow remains;
- PostgreSQL is a native GitHub Actions service with password auth;
- the integration test uses only `pg` plus repository SQL;
- the four RLS assertions and historical-upgrade behavior remain;
- no Testcontainers dependency remains;
- no custom Docker/`psql` orchestration remains;
- natural current-head `Controlled Runtime` PASS exists, or a non-code infrastructure blocker is explicitly recorded without retry;
- Active docs and PR body match the final architecture;
- PR remains unmerged unless separately authorized.
