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
- Open PR #387 changes many UI/current-state files but does not currently change `internal/webapp/runtime_test.go`, `internal/schemamigration/*`, the two integration workflows or the two shell scripts. Avoid unrelated UI/documentation edits that create conflict with #387.

**Upstream API references:**
- `https://golang.testcontainers.org/modules/postgres/`
- `https://golang.testcontainers.org/features/networking/`
- `https://golang.testcontainers.org/features/wait/http/`

---

### Task 1: Add Testcontainers at the reviewed version

**Files:**
- Modify: `go.mod`
- Modify: `go.sum`

**Interfaces:**
- Produces: Testcontainers core and PostgreSQL modules available only to test files.

- [ ] **Step 1: Add only the required modules**

```bash
go get github.com/testcontainers/testcontainers-go@v0.42.0 \
  github.com/testcontainers/testcontainers-go/modules/postgres@v0.42.0
go mod tidy
```

- [ ] **Step 2: Verify no pre-existing Go behavior regressed**

```bash
go test -count=1 ./...
```

Expected: PASS.

Do not commit yet; Task 2 consumes these dependencies.

---

### Task 2: Replace schema-migrator shell orchestration with a Go integration test

**Files:**
- Create: `internal/schemamigration/integration_test.go`
- Modify: `.github/workflows/schema-migrator.yml`
- Delete: `scripts/run-schema-migrator-test.sh`
- Modify: `go.mod`
- Modify: `go.sum`

**Interfaces:**
- Consumes: `schemamigration.Load`, `Open`, `Runner.Inspect`, `Runner.Apply`, `db/migrations.Files`.
- Produces: `TestRunnerAgainstPostgres`.

- [ ] **Step 1: Create package-local test helpers**

Start the file with:

```go
package schemamigration_test

import (
    "context"
    "net/url"
    "os"
    "path/filepath"
    "runtime"
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

Add these helpers in the test file only:

```go
func repositoryFile(t *testing.T, parts ...string) string {
    t.Helper()
    _, file, _, ok := runtime.Caller(0)
    if !ok {
        t.Fatal("resolve integration test path")
    }
    root := filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
    return filepath.Join(append([]string{root}, parts...)...)
}

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

func connectSimple(t *testing.T, ctx context.Context, databaseURL string) *pgx.Conn {
    t.Helper()
    config, err := pgx.ParseConfig(databaseURL)
    if err != nil {
        t.Fatal(err)
    }
    config.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
    conn, err := pgx.ConnectConfig(ctx, config)
    if err != nil {
        t.Fatal(err)
    }
    t.Cleanup(func() { _ = conn.Close(context.Background()) })
    return conn
}
```

- [ ] **Step 2: Start one PostgreSQL Testcontainer and create the migration identities**

Inside `TestRunnerAgainstPostgres`:

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
admin := connectSimple(t, ctx, adminURL)

for _, statement := range []string{
    "CREATE ROLE iwant_migrator NOLOGIN",
    "CREATE ROLE iwant_app_runtime NOLOGIN",
    "CREATE ROLE iwant_postgrest NOLOGIN",
    "CREATE ROLE iwant_authenticator LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION",
    "GRANT iwant_postgrest TO iwant_authenticator",
    "CREATE ROLE iwant_migration_runner LOGIN NOINHERIT PASSWORD 'iwant-migration-test'",
    "GRANT iwant_migrator TO iwant_migration_runner",
    "CREATE DATABASE iwant OWNER iwant_migrator",
    "CREATE DATABASE iwant_concurrent OWNER iwant_migrator",
} {
    if _, err := admin.Exec(ctx, statement); err != nil {
        t.Fatalf("setup PostgreSQL with %q: %v", statement, err)
    }
}

migrations, err := schemamigration.Load(repositorymigrations.Files)
if err != nil {
    t.Fatal(err)
}
```

- [ ] **Step 3: Preserve superuser rejection and initial-status behavior**

```go
superuserURL := databaseURL(t, adminURL, "postgres", password, "iwant")
runner, err := schemamigration.Open(ctx, superuserURL)
if runner != nil {
    _ = runner.Close(ctx)
}
if err == nil || !strings.Contains(err.Error(), "PostgreSQL superuser credentials are forbidden for schema migration") {
    t.Fatalf("expected superuser rejection, got %v", err)
}

migrationURL := databaseURL(t, adminURL, "iwant_migration_runner", password, "iwant")
runner, err = schemamigration.Open(ctx, migrationURL)
if err != nil {
    t.Fatal(err)
}
defer runner.Close(context.Background())

status, err := runner.Inspect(ctx, migrations)
if err != nil {
    t.Fatal(err)
}
if status.Applied != 0 || len(status.Pending) != len(migrations) {
    t.Fatalf("initial status = applied %d pending %d, want 0/%d", status.Applied, len(status.Pending), len(migrations))
}

adminTarget := connectSimple(t, ctx, superuserURL)
var historyMissing bool
if err := adminTarget.QueryRow(ctx, "SELECT to_regclass('iwant_migration.schema_migration') IS NULL").Scan(&historyMissing); err != nil {
    t.Fatal(err)
}
if !historyMissing {
    t.Fatal("status unexpectedly created migration history")
}
```

- [ ] **Step 4: Preserve apply, idempotency, verify and target-schema behavior**

```go
first, err := runner.Apply(ctx, migrations)
if err != nil {
    t.Fatal(err)
}
if got, want := len(first.Applied), len(migrations); got != want {
    t.Fatalf("first apply = %d migrations, want %d", got, want)
}

second, err := runner.Apply(ctx, migrations)
if err != nil {
    t.Fatal(err)
}
if got := len(second.Applied); got != 0 {
    t.Fatalf("second apply newly applied = %d, want 0", got)
}

status, err = runner.Inspect(ctx, migrations)
if err != nil {
    t.Fatal(err)
}
if len(status.Pending) != 0 || status.Applied != len(migrations) {
    t.Fatalf("final status = applied %d pending %d", status.Applied, len(status.Pending))
}

targetSchema, err := os.ReadFile(repositoryFile(t, "db", "tests", "target_schema.sql"))
if err != nil {
    t.Fatal(err)
}
if _, err := adminTarget.Exec(ctx, string(targetSchema)); err != nil {
    t.Fatalf("target schema assertion: %v", err)
}

var historyCount int
if err := adminTarget.QueryRow(ctx, "SELECT count(*) FROM iwant_migration.schema_migration").Scan(&historyCount); err != nil {
    t.Fatal(err)
}
if historyCount != len(migrations) {
    t.Fatalf("history rows = %d, want %d", historyCount, len(migrations))
}
```

- [ ] **Step 5: Preserve concurrent apply**

```go
concurrentURL := databaseURL(t, adminURL, "iwant_migration_runner", password, "iwant_concurrent")
runners := make([]*schemamigration.Runner, 2)
for i := range runners {
    runners[i], err = schemamigration.Open(ctx, concurrentURL)
    if err != nil {
        t.Fatal(err)
    }
    defer runners[i].Close(context.Background())
}

var wg sync.WaitGroup
errs := make(chan error, len(runners))
for _, concurrentRunner := range runners {
    wg.Add(1)
    go func(r *schemamigration.Runner) {
        defer wg.Done()
        _, applyErr := r.Apply(ctx, migrations)
        errs <- applyErr
    }(concurrentRunner)
}
wg.Wait()
close(errs)
for applyErr := range errs {
    if applyErr != nil {
        t.Fatal(applyErr)
    }
}

adminConcurrent := connectSimple(t, ctx, databaseURL(t, adminURL, "postgres", password, "iwant_concurrent"))
if err := adminConcurrent.QueryRow(ctx, "SELECT count(*) FROM iwant_migration.schema_migration").Scan(&historyCount); err != nil {
    t.Fatal(err)
}
if historyCount != len(migrations) {
    t.Fatalf("concurrent history rows = %d, want %d", historyCount, len(migrations))
}
```

- [ ] **Step 6: Preserve checksum-drift detection**

```go
if _, err := adminTarget.Exec(ctx,
    "UPDATE iwant_migration.schema_migration SET checksum_sha256 = repeat('0', 64) WHERE version = 1",
); err != nil {
    t.Fatal(err)
}
_, err = runner.Inspect(ctx, migrations)
if err == nil || !strings.Contains(err.Error(), "applied migration 000001 checksum changed") {
    t.Fatalf("expected checksum drift error, got %v", err)
}
```

- [ ] **Step 7: Run the Go integration test before deleting shell**

```bash
go test -count=1 -run TestRunnerAgainstPostgres ./internal/schemamigration
```

Expected: PASS.

- [ ] **Step 8: Point CI at the Go test and delete the shell**

In `.github/workflows/schema-migrator.yml`, use these path consumers:

```yaml
      - 'go.mod'
      - 'go.sum'
      - 'cmd/iwant-migrate/**'
      - 'db/migrations/**'
      - 'db/tests/target_schema.sql'
      - 'internal/schemamigration/**'
      - '.github/workflows/schema-migrator.yml'
```

and this step:

```yaml
      - name: Run schema migrator integration gate
        run: go test -count=1 -run TestRunnerAgainstPostgres ./internal/schemamigration
```

Keep `runs-on: ci-container` and `DOCKER_HOST`. Delete `scripts/run-schema-migrator-test.sh`.

- [ ] **Step 9: Verify and commit the schema-migrator tranche**

```bash
go test -count=1 -run TestRunnerAgainstPostgres ./internal/schemamigration
go test -count=1 ./...
git add go.mod go.sum internal/schemamigration/integration_test.go .github/workflows/schema-migrator.yml
git rm scripts/run-schema-migrator-test.sh
git commit -m "test: move schema migrator integration to Testcontainers"
```

---

### Task 3: Extract controlled-runtime fixture and database assertions from shell

**Files:**
- Create: `internal/webapp/testdata/controlled-runtime-fixture.sql`
- Create: `internal/webapp/testdata/controlled-runtime-assertions.sql`

**Interfaces:**
- Produces: SQL consumed only by the controlled-runtime Go test.

- [ ] **Step 1: Extract the existing fixture without semantic changes**

Copy the SQL from the current shell beginning with:

```sql
BEGIN;
SELECT set_config('iwant.actor_identifier', 'test:runtime-fixture', true);
SELECT set_config('iwant.audit_reason', 'Create controlled runtime people', true);
```

through its `COMMIT;` into `internal/webapp/testdata/controlled-runtime-fixture.sql`, then append:

```sql
ALTER ROLE iwant_authenticator PASSWORD 'iwant-runtime';
```

- [ ] **Step 2: Extract the existing post-browser database assertions**

Copy the final `DO $$ ... $$;` assertion block from `scripts/run-piloti-runtime-test.sh` into `internal/webapp/testdata/controlled-runtime-assertions.sql` unchanged.

Do not copy the `iwant.controlled-runtime.v1` JSON report generation.

- [ ] **Step 3: Verify key existing invariants remain in the extracted files**

```bash
grep -F "Create controlled runtime people" internal/webapp/testdata/controlled-runtime-fixture.sql
grep -F "expected attributed browser person mutation audit events" internal/webapp/testdata/controlled-runtime-assertions.sql
grep -F "expected closed Costi period to reject normal expense insert" internal/webapp/testdata/controlled-runtime-assertions.sql
```

Expected: PASS.

Do not commit until Task 4 consumes these files.

---

### Task 4: Make the browser controlled-runtime test own PostgreSQL/PostgREST lifecycle

**Files:**
- Modify: `internal/webapp/runtime_test.go`
- Create: `internal/webapp/runtime_environment_test.go`
- Consume: `internal/webapp/testdata/controlled-runtime-fixture.sql`
- Consume: `internal/webapp/testdata/controlled-runtime-assertions.sql`

**Interfaces:**
- Produces: `startControlledRuntime(t *testing.T) *controlledRuntimeEnvironment`.
- `controlledRuntimeEnvironment` exposes only `postgrestURL`, `jwtSecret`, and `databaseURL` to its own package test.
- `(*controlledRuntimeEnvironment).verify(t *testing.T)` executes the extracted post-browser SQL assertions.

- [ ] **Step 1: Create the focused package-local environment helper**

Use:

```go
package webapp

import (
    "context"
    "net"
    "os"
    "path/filepath"
    "runtime"
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

type controlledRuntimeEnvironment struct {
    postgrestURL string
    jwtSecret   []byte
    databaseURL string
}

func webappTestFile(t *testing.T, parts ...string) string {
    t.Helper()
    _, file, _, ok := runtime.Caller(0)
    if !ok {
        t.Fatal("resolve controlled runtime test path")
    }
    root := filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
    return filepath.Join(append([]string{root}, parts...)...)
}

func connectControlledRuntimeDB(t *testing.T, ctx context.Context, databaseURL string) *pgx.Conn {
    t.Helper()
    config, err := pgx.ParseConfig(databaseURL)
    if err != nil {
        t.Fatal(err)
    }
    config.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
    conn, err := pgx.ConnectConfig(ctx, config)
    if err != nil {
        t.Fatal(err)
    }
    t.Cleanup(func() { _ = conn.Close(context.Background()) })
    return conn
}
```

This helper is test-only and package-local; do not move it into production packages or a shared integration framework.

- [ ] **Step 2: Start a throw-away network and PostgreSQL**

```go
func startControlledRuntime(t *testing.T) *controlledRuntimeEnvironment {
    t.Helper()
    ctx := context.Background()

    nw, err := network.New(ctx)
    if err != nil {
        t.Fatal(err)
    }
    testcontainers.CleanupNetwork(t, nw)

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

    databaseURL, err := postgresContainer.ConnectionString(ctx, "sslmode=disable")
    if err != nil {
        t.Fatal(err)
    }
    database := connectControlledRuntimeDB(t, ctx, databaseURL)

    migrations, err := schemamigration.Load(repositorymigrations.Files)
    if err != nil {
        t.Fatal(err)
    }
    for _, migration := range migrations {
        if _, err := database.Exec(ctx, migration.SQL); err != nil {
            t.Fatalf("apply %s: %v", migration.Filename, err)
        }
    }

    fixture, err := os.ReadFile(webappTestFile(t, "internal", "webapp", "testdata", "controlled-runtime-fixture.sql"))
    if err != nil {
        t.Fatal(err)
    }
    if _, err := database.Exec(ctx, string(fixture)); err != nil {
        t.Fatalf("controlled runtime fixture: %v", err)
    }
```

Continue the same function in Step 3.

- [ ] **Step 3: Start PostgREST on the same network and return host-side connection data**

Append:

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

    host, err := postgrestContainer.Host(ctx)
    if err != nil {
        t.Fatal(err)
    }
    port, err := postgrestContainer.MappedPort(ctx, "3000/tcp")
    if err != nil {
        t.Fatal(err)
    }

    return &controlledRuntimeEnvironment{
        postgrestURL: "http://" + net.JoinHostPort(host, port.Port()),
        jwtSecret:   []byte(jwtSecret),
        databaseURL: databaseURL,
    }
}
```

Do not assume `localhost` or a fixed mapped port.

- [ ] **Step 4: Implement database verification from the extracted SQL**

```go
func (environment *controlledRuntimeEnvironment) verify(t *testing.T) {
    t.Helper()
    ctx := context.Background()
    database := connectControlledRuntimeDB(t, ctx, environment.databaseURL)
    assertions, err := os.ReadFile(webappTestFile(t, "internal", "webapp", "testdata", "controlled-runtime-assertions.sql"))
    if err != nil {
        t.Fatal(err)
    }
    if _, err := database.Exec(ctx, string(assertions)); err != nil {
        t.Fatalf("controlled runtime database assertions: %v", err)
    }
}
```

- [ ] **Step 5: Replace the external-env skip in `runtime_test.go`**

Replace:

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

Remove the now-unused `os` import from `runtime_test.go` only if no other code in that file consumes it.

After the existing browser behavior/mutations have completed, call:

```go
runtime.verify(t)
```

Do not alter the existing browser assertions themselves.

- [ ] **Step 6: Run the Go-controlled runtime before deleting shell**

```bash
go test -count=1 -run TestControlledRuntimeBrowserActorReachesPostgreSQL ./internal/webapp
```

Expected: PASS.

---

### Task 5: Delete controlled-runtime shell lifecycle and simplify CI

**Files:**
- Modify: `.github/workflows/piloti-runtime.yml`
- Delete: `scripts/run-piloti-runtime-test.sh`
- Add: `internal/webapp/runtime_environment_test.go`
- Add: `internal/webapp/testdata/controlled-runtime-fixture.sql`
- Add: `internal/webapp/testdata/controlled-runtime-assertions.sql`
- Modify: `internal/webapp/runtime_test.go`
- Modify: `go.mod`
- Modify: `go.sum`

**Interfaces:**
- Consumes: self-contained Go test from Task 4.
- Produces: direct CI invocation with no shell-owned lifecycle/report.

- [ ] **Step 1: Update path filters**

Keep existing product paths and ensure these are present once:

```yaml
      - 'go.mod'
      - 'go.sum'
      - 'internal/webapp/**'
      - '.github/workflows/piloti-runtime.yml'
```

Remove `scripts/run-piloti-runtime-test.sh` from both push and pull-request filters.

- [ ] **Step 2: Replace the shell step**

Use:

```yaml
      - name: Run browser-to-PostgreSQL controlled runtime test
        run: go test -count=1 -run TestControlledRuntimeBrowserActorReachesPostgreSQL ./internal/webapp
```

Remove `RUNTIME_DEBUG`; keep `ci-container` and `DOCKER_HOST`.

- [ ] **Step 3: Delete the superseded shell and report generation**

```bash
git rm scripts/run-piloti-runtime-test.sh
```

No `CONTROLLED_RUNTIME_REPORT_PATH` or `iwant.controlled-runtime.v1` replacement is created.

- [ ] **Step 4: Verify both integration tests and the ordinary suite**

```bash
go test -count=1 -run TestRunnerAgainstPostgres ./internal/schemamigration
go test -count=1 -run TestControlledRuntimeBrowserActorReachesPostgreSQL ./internal/webapp
go test -count=1 ./...
```

Expected: PASS.

- [ ] **Step 5: Confirm active CI has no retired shell references**

```bash
! grep -R "run-schema-migrator-test.sh\|run-piloti-runtime-test.sh\|CONTROLLED_RUNTIME_REPORT_PATH\|iwant.controlled-runtime.v1" \
  .github internal scripts --exclude-dir=.git
```

Expected: PASS.

- [ ] **Step 6: Commit the controlled-runtime tranche**

```bash
git add go.mod go.sum .github/workflows/piloti-runtime.yml \
  internal/webapp/runtime_test.go internal/webapp/runtime_environment_test.go \
  internal/webapp/testdata/controlled-runtime-fixture.sql \
  internal/webapp/testdata/controlled-runtime-assertions.sql
git commit -m "test: move controlled runtime lifecycle to Testcontainers"
```

---

### Task 6: Verify current-head CI without retries

**Files:**
- No new files.

**Interfaces:**
- Consumes: exact iWant Task 9 PR head.
- Produces: natural-run evidence for both integration workflows.

- [ ] **Step 1: Push only after focused and full local suites are green**

Do not invoke `workflow_dispatch` to compensate for a normal path-filtered PR run.

- [ ] **Step 2: Inspect natural `Schema Migrator` and `Controlled Runtime` runs**

Acceptance for each:

```text
ci-container assigned;
checkout started;
Go setup completed;
focused integration test PASS;
no shell orchestration step;
no manual rerun.
```

If a job has zero steps or no runner assignment, stop as infrastructure according to RFC §8.

- [ ] **Step 3: Diagnose by ownership before editing**

Lifecycle failures are Docker/provider/image/network/readiness failures. Domain failures are migration privilege/history/checksum, PostgREST/auth, browser behavior, or audit SQL failures. Do not add sleeps/retries before classification.

---

### Task 7: Reconcile active docs against then-current main

**Files:**
- Re-fetch before editing: `README.md`
- Re-fetch before editing: `docs/project/current-state.md`
- Update: Task 9 PR body

**Interfaces:**
- Consumes: verified code plus then-current state of PR #387/main.
- Produces: no active source claiming shell-owned integration lifecycle.

- [ ] **Step 1: Re-fetch current `main` because PR #387 currently modifies both active docs**

Do not copy pre-#387 documentation text into a new branch.

- [ ] **Step 2: Change only integration-runtime statements to the verified result**

Use this exact operational meaning:

```text
Schema Migrator and Controlled Runtime remain separate behavioral gates on ci-container.
Their PostgreSQL/PostgREST lifecycle is test-owned through Testcontainers for Go.
Schema migration assertions cover superuser rejection, idempotency, concurrency,
target schema and checksum drift. Controlled Runtime covers the browser/API/PostgREST/
PostgreSQL path and database audit invariants. No shell Docker orchestration or
reconciliation-report artifact is part of steady state.
```

Do not modify unrelated UI-wave history.

- [ ] **Step 3: Verify active references and commit**

```bash
! grep -R "run-schema-migrator-test.sh\|run-piloti-runtime-test.sh\|iwant.controlled-runtime.v1" \
  README.md docs/project/current-state.md .github internal scripts --exclude-dir=.git
git add README.md docs/project/current-state.md
git commit -m "docs: align iWant integration runtime ownership"
```

Archived historical evidence may retain old names only when clearly marked Archived.

---

## Completion Gate

- both real integration behaviors remain covered;
- both in-scope lifecycle shell scripts are gone from active CI;
- no manual Docker network/run/readiness/port/cleanup shell remains for these gates;
- Testcontainers is called directly from Go tests without a shared framework;
- `scripts/run-migration-rehearsal.sh` is untouched;
- unused reconciliation-report JSON is gone;
- focused tests and `go test -count=1 ./...` pass where Docker is available;
- natural current-head CI is inspected without rerun;
- active docs match the final state after reconciling with then-current main;
- PR remains unmerged unless separately authorized.
