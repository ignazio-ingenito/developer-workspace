> **Archived 2026-08-12.** Historical execution plan for the availability-first transition. Superseded by current `main` after PR #18/#19 and the Homelab runtime cutover #709. Do not use this file as executable instructions.

# Developer Workspace Availability-First CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** costruire una sola volta l'immagine `developer-workspace`, verificare quell'esatto artifact con smoke test, Playwright e Trivy, quindi pubblicare lo stesso artifact senza esporre permessi package-write alla fase di verifica.

**Architecture:** il job `verify` ha soli permessi read-only, produce `/tmp/developer-workspace.tar`, testa e scansiona l'immagine e conserva il tar solo sugli eventi di push. Il job `publish`, eseguito solo dopo `verify` verde su `main` o tag `v*`, scarica il tar verificato e lo pubblica con `packages: write` senza rebuild.

**Tech Stack:** GitHub Actions, Docker Buildx, Docker CLI, Trivy, mise.

## Global Constraints

- Policy: availability-first approvata in `ignazio-ingenito/homelab#677`.
- Reporting: `HIGH,CRITICAL`, `ignore-unfixed: false`, `os,library`, `exit-code: 0`.
- Gate: `HIGH,CRITICAL`, `ignore-unfixed: true`, `os,library`, `exit-code: 1`.
- Invariante: `build once → verify exact artifact → publish exact artifact`.
- `verify`: `contents: read`, nessun `packages: write`.
- `publish`: `packages: write` solo su push `main`/tag.
- Passare `MISE_GITHUB_TOKEN` read-only ai container di smoke/Playwright per evitare rate limit anonimi.
- Preservare smoke test e Playwright Chromium reale.
- Preservare i tag `latest`, `sha-${GITHUB_SHA}` e `v*` già esposti.
- Non modificare il deployment GitOps `:latest` in questo PR.
- Nessuna allowlist generica.
- Nessun merge automatico.

---

### Task 1: pipeline exact-artifact e gate availability-first

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `Dockerfile`, `scripts/smoke-test.sh`, `scripts/test-playwright-runtime.sh`.
- Produces: `/tmp/developer-workspace.tar` e immagine locale `developer-workspace:sha-${GITHUB_SHA}`.

- [x] **Step 1: verificare il contratto precedente**

Baseline: tre invocazioni potenziali di `docker/build-push-action` (build/test, publish main, publish tag).

- [x] **Step 2: build singolo con export dell'artifact**

Un solo `docker/build-push-action`, con tag locale, revision label e `outputs: type=docker,dest=/tmp/developer-workspace.tar`.

- [x] **Step 3: load e test sullo stesso artifact**

`docker load` precede smoke e Playwright; entrambi usano `developer-workspace:sha-${GITHUB_SHA}`.

- [x] **Step 4: rendere robusto `mise install` in CI**

Il primo run reale ha fallito nello smoke perché `mise` ha raggiunto il rate limit GitHub anonimo (`403`, `0/60`). La correzione passa `MISE_GITHUB_TOKEN=${{ github.token }}` ai container di test, mantenendo il job `verify` read-only.

- [x] **Step 5: report Trivy completo non bloccante**

`ignore-unfixed: false`, `exit-code: '0'`.

- [x] **Step 6: gate Trivy fixable bloccante**

`ignore-unfixed: true`, `exit-code: '1'`.

- [x] **Step 7: verifica revision label**

La label `org.opencontainers.image.revision` deve coincidere con `GITHUB_SHA` prima che l'artifact sia considerato verificato.

- [x] **Step 8: separazione least-privilege del publish**

Il job `verify` conserva il tar solo su push. Il job `publish` ha `packages: write`, scarica lo stesso tar, ricontrolla la revision label e retagga/pusha senza build.

- [ ] **Step 9: verifica reale PR**

Atteso nel job `verify`:

```text
Lint shell scripts
Build exact image artifact
Load exact image artifact
Smoke test
Playwright Chromium acceptance
Report HIGH/CRITICAL vulnerabilities
Block fixable HIGH/CRITICAL vulnerabilities
Verify exact image artifact
```

Su PR `Preserve verified image artifact` e l'intero job `publish` devono essere skipped.

- [ ] **Step 10: se il gate Trivy fallisce, remediation guidata dai finding**

Modificare Dockerfile/base image solo per `HIGH/CRITICAL` fixable emerse dal gate. Nessuna remediation basata sul conteggio aggregato Harbor.

### Task 2: verificare l'integrazione post-merge

Questa task non viene eseguita senza merge esplicitamente richiesto.

- [ ] Dopo merge verificare il run naturale `main`.
- [ ] Verificare upload/download del tar e publish senza rebuild.
- [ ] Verificare che `latest` e `sha-${GITHUB_SHA}` puntino all'artifact validato.
- [ ] Verificare replica e scan Harbor.
- [ ] Verificare che CVE senza fix non blocchino il workload secondo la policy #677.
- [ ] Verificare `developer-workspace-0` Ready e Playwright Chromium funzionante.
