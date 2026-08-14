# Task 9 — iWant Integration Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Draft  
**Mission:** `ignazio-ingenito/developer-workspace#33` — Task 9

**Goal:** Replace iWant's shell-owned PostgreSQL/PostgREST lifecycle with Testcontainers for Go while preserving the schema-migrator and browser→PostgREST→PostgreSQL behavior assertions that protect real failures.

**Architecture:** Integration lifecycle moves into Go tests. The schema-migrator test uses the official Testcontainers PostgreSQL module and calls `schemamigration.Open/Inspect/Apply` directly. The controlled-runtime test creates a throw-away Testcontainers network, PostgreSQL and PostgREST, applies repository migrations/fixtures, runs the existing browser behavior against the mapped PostgREST URL, then verifies database audit invariants. Shell scripts and generated reconciliation-report JSON disappear.

**Tech Stack:** Go 1.26, `github.com/testcontainers/testcontainers-go` v0.42.0, official Testcontainers PostgreSQL module v0.42.0, pgx v5, PostgreSQL 16, PostgREST v14.14.

## Global Constraints

- RFC-0001 v0.1.6 is authoritative.
- Keep `postgres:16` and `postgrest/postgrest:v14.14` as currently used by `main`; do not mix dependency/image upgrades into Task 9.
- Testcontainers v0.42.0 is the currently verified upstream release for this plan; use the official Postgres module and generic container/network/wait APIs only.
- Do not build an internal Testcontainers framework or a cross-repository abstraction.
- Domain fixtures/assertions may move from shell heredocs into test/testdata files; their behavior must not be weakened merely to shorten code.
- Delete lifecycle shell only after the equivalent Go test is green.
- Delete `iwant.controlled-runtime.v1` report generation: repository search found no consumer outside `run-piloti-runtime-test.sh`.
- Keep `ci-container`; Testcontainers requires the existing Docker-capable runner.
- No GitHub Actions rerun. New commits may trigger natural runs.
- Do not touch `scripts/run-migration-rehearsal.sh`; no current CI workflow consumes it, so it is outside this Task 9 tranche.
- Open PR #387 changes many UI/current-state files but does not currently change the target integration files `internal/webapp/runtime_test.go`, `internal/schemamigration/*`, the two integration workflows or the two shell scripts. Avoid unrelated UI/documentation edits that create conflict with #387.

**Upstream API references:**
- `https://golang.testcontainers.org/modules/postgres/`
- `https://golang.testcontainers.org/features/networking/`
- `https://golang.testcontainers.org/features/wait/http/`

---

### Task 1: Add the Testcontainers dependencies without changing runtime behavior

**Files:**
- Modify: `go.mod`
- Modify: `go.sum`

**Interfaces:**
- Produces: official Testcontainers core and PostgreSQL modules available to `_test.go` files.

- [ ] **Step 1: Add only the required modules at the reviewed version**

Run:

```bash
go get github.com/testcontainers/testcontainers-go@v0.42.0 \
  github.com/testcontainers/testcontainers-go/modules/postgres@v0.42.0
```

- [ ] **Step 2: Normalize modules**

Run:

```bash
go mod tidy
```

- [ ] **Step 3: Verify the ordinary Go suite still passes before integration code changes**

Run:

```bash
go test -count=1 ./...
```

Expected: PASS.

- [ ] **Step 4: Commit dependency setup together with the first test task, not as a standalone feature commit**

Do not commit yet; dependency changes are consumed by Task 2.

---

### Task 2: Replace schema-migrator shell orchestration with a package integration test

**Files:**
- Create: `internal/schemamigration/integration_test.go`
- Modify: `.github/workflows/schema-migrator.yml`
- Delete: `scripts/run-schema-migrator-test.sh`
- Modify: `go.mod`
- Modify: `go.sum`

**Interfaces:**
- Consumes: `schemamigration.Load`, `Open`, `Runner.Inspect`, `Runner.Apply`, repository `db/migrations.Files`.
- Produces: Go test `TestRunnerAgainstPostgres` that owns one PostgreSQL Testcontainer and verifies the former script's real behaviors.

- [ ] **Step 1: Write the integration test while the shell gate still exists**

Create `internal/schemamigration/integration_test.go` with package `schemamigration_test` and these imports/boundaries:

```go
package schemamigration_test

import (
    "context"
    "net/url"
    "os"
    "strings"
    "sync"
    "testing"

    repositorymigrations "github.com/ignazio-ingenito/iwant/db/migrations"
    "github.com/ignazio-ingenito/iwant/internal/schemamigration"
    "github.com/jackc/pgx/v5"
    "github.com/testcontainers/testcontainers-go"
    tcpostgres "github.com/testcontainers/testcontainers-go/modules/postgres"
)
```

Use a local test-only URL helper, not a reusable package:

```go
func databaseURL(t *testing.T, base, user, password, database string) string {
    t.Helper()
    parsed, err := url.Parse(base)
    if err != nil {
        t.Fatal(err)
    }
    parsed.User = url.UserPassword(user, password)
    parsed.Path = "/" + database
    query := parsed.Query()
    query.Set("sslmode", "disable")
    parsed.RawQuery = query.Encode()
    return parsed.String()
}
```

Start PostgreSQL using the official module:

```go
ctx := context.Background()
const password = "iwant-migration-test"

ctr, err := tcpostgres.Run(ctx,
    "postgres:16",
    tcpostgres.WithDatabase("postgres"),
    tcpostgres.WithUsername("postgres"),
    tcpostgres.WithPassword(password),
    tcpostgres.BasicWaitStrategies(),
)
if err != nil {
    t.Fatal(err)
}
testcontainers.CleanupContainer(t, ctr)

adminURL, err := ctr.ConnectionString(ctx, "sslmode=disable")
if err != nil {
    t.Fatal(err)
}
```

Create the same roles/databases as the shell script using individual `pgx.Conn.Exec` calls so `CREATE DATABASE` is never hidden inside a transaction:

```sql
CREATE ROLE iwant_migrator NOLOGIN;
CREATE ROLE iwant_app_runtime NOLOGIN;
CREATE ROLE iwant_postgrest NOLOGIN;
CREATE ROLE iwant_authenticator LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
GRANT iwant_postgrest TO iwant_authenticator;
CREATE ROLE iwant_migration_runner LOGIN NOINHERIT PASSWORD 'iwant-migration-test';
GRANT iwant_migrator TO iwant_migration_runner;
CREATE DATABASE iwant OWNER iwant_migrator;
CREATE DATABASE iwant_concurrent OWNER iwant_migrator;
```

Load the real migration set:

```go
migrations, err := schemamigration.Load(repositorymigrations.Files)
if err != nil {
    t.Fatal(err)
}
```

The test must contain these subtests with explicit assertions:

```go
t.Run("rejects superuser credentials", func(t *testing.T) {
    runner, err := schemamigration.Open(ctx, databaseURL(t, adminURL, "postgres", password, "iwant"))
    if runner != nil {
        _ = runner.Close(ctx)
    }
    if err == nil || !strings.Contains(err.Error(), "PostgreSQL superuser credentials are forbidden for schema migration") {
        t.Fatalf("expected superuser rejection, got %v", err)
    }
})
```

For the normal migration URL, call `Inspect` before apply and assert `Applied == 0`, all migrations are pending, and `to_regclass('iwant_migration.schema_migration') IS NULL` through a separate PostgreSQL connection.

Call `Apply` twice and assert:

```go
if got, want := len(first.Applied), len(migrations); got != want {
    t.Fatalf("first apply = %d migrations, want %d", got, want)
}
if got := len(second.Applied); got != 0 {
    t.Fatalf("second apply newly applied = %d, want 0", got)
}
```

Run `Inspect` after apply and require zero pending migrations.

Execute `db/tests/target_schema.sql` against the migrated `iwant` database using a `pgx.Conn` configured with `pgx.QueryExecModeSimpleProtocol`; this preserves the target-schema behavior without invoking `psql`.

For concurrency, open two independent `Runner` sessions against `iwant_concurrent` and call `Apply` simultaneously with a `sync.WaitGroup`. Both calls must return nil; afterward query `iwant_migration.schema_migration` and require exactly `len(migrations)` rows.

For checksum drift, update version 1 to `repeat('0', 64)`, then call `Inspect` and require an error containing `applied migration 000001 checksum changed`.

- [ ] **Step 2: Run the new test while the old shell test still exists**

Run:

```bash
go test -count=1 -run TestRunnerAgainstPostgres ./internal/schemamigration
```

Expected: PASS.

If Testcontainers cannot reach Docker, classify it as runner/local environment before modifying the test behavior.

- [ ] **Step 3: Simplify the workflow to call the Go integration test directly**

Change `.github/workflows/schema-migrator.yml` paths:

```yaml
      - 'go.mod'
      - 'go.sum'
      - 'cmd/iwant-migrate/**'
      - 'db/migrations/**'
      - 'db/tests/target_schema.sql'
      - 'internal/schemamigration/**'
      - '.github/workflows/schema-migrator.yml'
```

Remove the `scripts/run-schema-migrator-test.sh` path.

Replace:

```yaml
      - name: Run schema migrator integration gate
        run: bash scripts/run-schema-migrator-test.sh
```

with:

```yaml
      - name: Run schema migrator integration gate
        run: go test -count=1 -run TestRunnerAgainstPostgres ./internal/schemamigration
```

Keep `runs-on: ci-container` and `DOCKER_HOST` unchanged because the Go test now talks to Docker through Testcontainers.

- [ ] **Step 4: Delete the superseded shell script**

Delete:

```text
scripts/run-schema-migrator-test.sh
```

No replacement shell wrapper is allowed.

- [ ] **Step 5: Run the focused and ordinary Go suites**

Run:

```bash
go test -count=1 -run TestRunnerAgainstPostgres ./internal/schemamigration
go test -count=1 ./...
```

Expected: PASS.

- [ ] **Step 6: Commit the schema-migrator tranche**

```bash
git add go.mod go.sum internal/schemamigration/integration_test.go .github/workflows/schema-migrator.yml
git rm scripts/run-schema-migrator-test.sh
git commit -m "test: move schema migrator integration to Testcontainers"
```

---

### Task 3: Move controlled-runtime fixture and audit assertions out of shell heredocs

**Files:**
- Create: `internal/webapp/testdata/controlled-runtime-fixture.sql`
- Create: `internal/webapp/testdata/controlled-runtime-assertions.sql`
- Modify later: `internal/webapp/runtime_test.go`

**Interfaces:**
- Produces: repository-owned SQL fixture and post-run assertion scripts consumed only by the controlled-runtime Go test.

- [ ] **Step 1: Extract the pre-PostgREST fixture SQL verbatim from the current shell script**

Move the SQL beginning with:

```sql
BEGIN;
SELECT set_config('iwant.actor_identifier', 'test:runtime-fixture', true);
SELECT set_config('iwant.audit_reason', 'Create controlled runtime people', true);
```

through its matching `COMMIT;` into `internal/webapp/testdata/controlled-runtime-fixture.sql`.

Also include the existing role password operation as the last statement:

```sql
ALTER ROLE iwant_authenticator PASSWORD 'iwant-runtime';
```

Do not change fixture values or domain meaning in this task.

- [ ] **Step 2: Extract the post-browser verification SQL verbatim**

Move the final `DO $$ ... $$;` block that checks `core.audit_event`, lifecycle preservation, financial period closure and related invariants into:

```text
internal/webapp/testdata/controlled-runtime-assertions.sql
```

Do not copy the final JSON report generation; that report has no external consumer and is deleted.

- [ ] **Step 3: Verify the files contain the existing invariant messages**

Run:

```bash
grep -F "expected attributed browser person mutation audit events" internal/webapp/testdata/controlled-runtime-assertions.sql
grep -F "expected closed Costi period to reject normal expense insert" internal/webapp/testdata/controlled-runtime-assertions.sql
grep -F "Create controlled runtime people" internal/webapp/testdata/controlled-runtime-fixture.sql
```

Expected: all PASS.

Do not commit until the Go test consumes these files in Task 4.

---

### Task 4: Make the existing browser controlled-runtime test own PostgreSQL and PostgREST lifecycle

**Files:**
- Modify: `internal/webapp/runtime_test.go`
- Create: `internal/webapp/runtime_environment_test.go`
- Consume: `internal/webapp/testdata/controlled-runtime-fixture.sql`
- Consume: `internal/webapp/testdata/controlled-runtime-assertions.sql`

**Interfaces:**
- `startControlledRuntime(t *testing.T) *controlledRuntimeEnvironment`
- `controlledRuntimeEnvironment.postgrestURL string`
- `controlledRuntimeEnvironment.jwtSecret []byte`
- `(*controlledRuntimeEnvironment).verify(t *testing.T)` executes the post-browser SQL assertions.

`runtime_environment_test.go` is a package-local test helper, not a reusable framework; it exists only to keep container setup out of the already-large browser assertion file.

- [ ] **Step 1: Create the package-local environment helper**

Use these core imports:

```go
import (
    "context"
    "fmt"
    "net"
    "net/http"
    "os"
    "path/filepath"
    "testing"
    "time"

    repositorymigrations "github.com/ignazio-ingenito/iwant/db/migrations"
    "github.com/ignazio-ingenito/iwant/internal/schemamigration"
    "github.com/jackc/pgx/v5"
    "github.com/testcontainers/testcontainers-go"
    "github.com/testcontainers/testcontainers-go/network"
    tcpostgres "github.com/testcontainers/testcontainers-go/modules/postgres"
    "github.com/testcontainers/testcontainers-go/wait"
)
```

Define only the data required by the browser test:

```go
type controlledRuntimeEnvironment struct {
    postgrestURL string
    jwtSecret   []byte
    databaseURL string
}
```

Create a throw-away network:

```go
nw, err := network.New(ctx)
if err != nil {
    t.Fatal(err)
}
testcontainers.CleanupNetwork(t, nw)
```

Start PostgreSQL on that network with alias `postgres`:

```go
postgresContainer, err := tcpostgres.Run(ctx,
    "postgres:16",
    tcpostgres.WithDatabase("iwant"),
    tcpostgres.WithUsername("postgres"),
    tcpostgres.WithPassword("iwant-runtime"),
    tcpostgres.BasicWaitStrategies(),
    network.WithNetwork([]string{"postgres"}, nw),
)
if err != nil {
    t.Fatal(err)
}
testcontainers.CleanupContainer(t, postgresContainer)
```

Get the host-side connection string with:

```go
databaseURL, err := postgresContainer.ConnectionString(ctx, "sslmode=disable")
if err != nil {
    t.Fatal(err)
}
```

Connect with pgx simple protocol, load migrations via `schemamigration.Load(repositorymigrations.Files)` and execute each migration's SQL in order. Then read and execute `testdata/controlled-runtime-fixture.sql`.

Start PostgREST on the same network:

```go
const jwtSecret = "piloti-runtime-jwt-secret-32-bytes"
postgrestContainer, err := testcontainers.Run(ctx,
    "postgrest/postgrest:v14.14",
    network.WithNetwork([]string{"postgrest"}, nw),
    testcontainers.WithExposedPorts("3000/tcp"),
    testcontainers.WithEnv(map[string]string{
        "PGRST_DB_URI":     "postgres://iwant_authenticator:iwant-runtime@postgres:5432/iwant",
        "PGRST_DB_SCHEMAS": "api",
        "PGRST_JWT_SECRET": jwtSecret,
        "PGRST_JWT_AUD":    "iwant-postgrest",
    }),
    testcontainers.WithWaitStrategy(
        wait.ForHTTP("/").WithPort("3000/tcp").WithStartupTimeout(60*time.Second),
    ),
)
if err != nil {
    t.Fatal(err)
}
testcontainers.CleanupContainer(t, postgrestContainer)
```

Construct the host URL from `Host(ctx)` plus `MappedPort(ctx, "3000/tcp")`; do not assume localhost or a fixed host port:

```go
host, err := postgrestContainer.Host(ctx)
if err != nil {
    t.Fatal(err)
}
port, err := postgrestContainer.MappedPort(ctx, "3000/tcp")
if err != nil {
    t.Fatal(err)
}
postgrestURL := "http://" + net.JoinHostPort(host, port.Port())
```

Return the environment with `[]byte(jwtSecret)`.

- [ ] **Step 2: Make `verify` execute the extracted audit assertions directly**

`verify` opens `databaseURL` with pgx simple protocol, reads:

```text
internal/webapp/testdata/controlled-runtime-assertions.sql
```

and executes it. Any PostgreSQL exception fails the Go test directly. Do not generate `iwant.controlled-runtime.v1` JSON.

- [ ] **Step 3: Remove the environment-variable skip from the browser test**

At the start of `TestControlledRuntimeBrowserActorReachesPostgreSQL`, replace:

```go
postgrestURL := os.Getenv("IWANT_RUNTIME_TEST_POSTGREST_URL")
if postgrestURL == "" {
    t.Skip("set IWANT_RUNTIME_TEST_POSTGREST_URL to run the controlled runtime test")
}
jwtKey := []byte(os.Getenv("IWANT_RUNTIME_TEST_JWT_SECRET"))
```

with:

```go
runtime := startControlledRuntime(t)
postgrestURL := runtime.postgrestURL
jwtKey := runtime.jwtSecret
```

After all existing browser mutations/assertions complete, call:

```go
runtime.verify(t)
```

The existing browser assertions themselves remain unchanged.

- [ ] **Step 4: Run the controlled runtime test while the shell script still exists**

Run:

```bash
go test -count=1 -run TestControlledRuntimeBrowserActorReachesPostgreSQL ./internal/webapp
```

Expected: PASS with Testcontainers owning PostgreSQL/PostgREST lifecycle.

- [ ] **Step 5: Verify the generated report has no remaining consumer**

Run:

```bash
! grep -R "CONTROLLED_RUNTIME_REPORT_PATH\|iwant.controlled-runtime.v1\|W14 controlled runtime reconciliation report" \
  --exclude='run-piloti-runtime-test.sh' .
```

Expected: PASS.

---

### Task 5: Delete the controlled-runtime shell lifecycle and simplify its workflow

**Files:**
- Modify: `.github/workflows/piloti-runtime.yml`
- Delete: `scripts/run-piloti-runtime-test.sh`
- Modify: `go.mod`
- Modify: `go.sum`
- Add from previous tasks: `internal/webapp/runtime_environment_test.go`
- Add from previous tasks: `internal/webapp/testdata/controlled-runtime-fixture.sql`
- Add from previous tasks: `internal/webapp/testdata/controlled-runtime-assertions.sql`

**Interfaces:**
- Consumes: the self-contained Go controlled-runtime test from Task 4.
- Produces: one workflow step that runs that test directly.

- [ ] **Step 1: Update path filters for actual consumers**

In `.github/workflows/piloti-runtime.yml`, remove:

```yaml
      - 'scripts/run-piloti-runtime-test.sh'
```

and add:

```yaml
      - 'go.mod'
      - 'go.sum'
      - 'internal/webapp/**'
```

`internal/webapp/**` already exists in `main`; keep only one copy.

- [ ] **Step 2: Replace the shell invocation**

Replace:

```yaml
      - name: Run browser-to-PostgreSQL controlled runtime test
        env:
          RUNTIME_DEBUG: '1'
        run: scripts/run-piloti-runtime-test.sh
```

with:

```yaml
      - name: Run browser-to-PostgreSQL controlled runtime test
        run: go test -count=1 -run TestControlledRuntimeBrowserActorReachesPostgreSQL ./internal/webapp
```

Keep `runs-on: ci-container` and `DOCKER_HOST` because Testcontainers consumes Docker.

- [ ] **Step 3: Delete the shell script**

Delete:

```text
scripts/run-piloti-runtime-test.sh
```

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
go test -count=1 -run TestControlledRuntimeBrowserActorReachesPostgreSQL ./internal/webapp
go test -count=1 ./...
```

Expected: PASS.

- [ ] **Step 5: Confirm no active CI path references either retired shell script**

Run:

```bash
! grep -R "run-schema-migrator-test.sh\|run-piloti-runtime-test.sh" .github internal scripts --exclude-dir=.git
```

Expected: PASS.

- [ ] **Step 6: Commit the controlled-runtime tranche**

```bash
git add go.mod go.sum .github/workflows/piloti-runtime.yml \
  internal/webapp/runtime_test.go internal/webapp/runtime_environment_test.go \
  internal/webapp/testdata/controlled-runtime-fixture.sql \
  internal/webapp/testdata/controlled-runtime-assertions.sql
git rm scripts/run-piloti-runtime-test.sh
git commit -m "test: move controlled runtime lifecycle to Testcontainers"
```

---

### Task 6: Verify current-head CI without retries

**Files:**
- No new files.

**Interfaces:**
- Consumes: exact Task 9 iWant PR head.
- Produces: natural-run evidence for both integration workflows.

- [ ] **Step 1: Push the branch once the local focused/full suites are green**

Do not invoke workflow dispatch to compensate for a missing natural run if the path filters already match the changed files.

- [ ] **Step 2: Inspect natural `Schema Migrator` and `Controlled Runtime` runs**

Acceptance for each:

- job starts on `ci-container`;
- checkout and Go setup run normally;
- focused Go integration test PASS;
- no shell orchestration step exists;
- no manual rerun is performed.

If a job has no steps/runner assignment, stop as infrastructure according to RFC §8.

- [ ] **Step 3: Treat Testcontainers lifecycle failure separately from domain failure**

Lifecycle class:

- Docker/provider unavailable;
- image pull unavailable;
- network/container readiness failure.

Domain class:

- migration privilege/history/checksum failure;
- PostgREST connection/auth failure;
- browser behavior failure;
- audit/domain SQL assertion failure.

Do not add retries or sleeps until the failure class is known.

---

### Task 7: Reconcile active documentation after code is integrated with current main

**Files:**
- Re-evaluate: `README.md`
- Re-evaluate: `docs/project/current-state.md`
- Update: Task 9 PR body

**Interfaces:**
- Consumes: verified integration implementation and then-current `main`/open-PR state.
- Produces: no active source claiming shell-owned lifecycle.

- [ ] **Step 1: Re-fetch current `main` before editing docs**

PR #387 currently modifies both `README.md` and `docs/project/current-state.md`; do not base documentation edits on stale pre-#387 text.

- [ ] **Step 2: Update only active integration-runtime statements**

The resulting current-state statement must say, in substance:

```text
Schema Migrator and Controlled Runtime remain separate behavioral gates on ci-container.
Their PostgreSQL/PostgREST lifecycle is test-owned through Testcontainers for Go.
Schema migration assertions cover privilege rejection, idempotency, concurrency,
target schema and checksum drift. Controlled Runtime covers the browser/API/PostgREST/
PostgreSQL path and database audit invariants. No shell Docker orchestration or
reconciliation-report artifact is part of steady state.
```

Do not alter unrelated UI-wave history.

- [ ] **Step 3: Verify active references**

Run:

```bash
! grep -R "run-schema-migrator-test.sh\|run-piloti-runtime-test.sh\|iwant.controlled-runtime.v1" \
  README.md docs/project/current-state.md .github internal scripts --exclude-dir=.git
```

Expected: PASS, except explicitly archived historical evidence if present and clearly marked Archived.

- [ ] **Step 4: Commit documentation reconciliation separately**

```bash
git add README.md docs/project/current-state.md
git commit -m "docs: align iWant integration runtime ownership"
```

---

## Completion Gate

iWant Task 9 tranche is ready when all are true:

- both real integration behaviors remain covered;
- `run-schema-migrator-test.sh` and `run-piloti-runtime-test.sh` are gone from active CI;
- no manual Docker network/run/readiness/port/cleanup shell remains for the in-scope gates;
- Testcontainers is used directly from Go tests without an internal wrapper framework;
- `scripts/run-migration-rehearsal.sh` remains untouched;
- unused reconciliation-report JSON is gone;
- focused tests and `go test -count=1 ./...` pass locally where Docker is available;
- natural current-head CI is inspected without rerun;
- active docs match the final state after reconciling with then-current main;
- PR remains unmerged unless separately authorized.
