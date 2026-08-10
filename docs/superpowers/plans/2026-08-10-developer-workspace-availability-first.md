# Developer Workspace Availability-First CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** costruire una sola volta l'immagine `developer-workspace`, verificare quell'esatto artifact con smoke test, Playwright e Trivy, quindi pubblicare lo stesso artifact.

**Architecture:** un singolo job GitHub Actions esporta l'immagine in `/tmp/developer-workspace.tar`, la carica in Docker, esegue i test, un report Trivy completo non bloccante e un gate Trivy sulle sole vulnerabilità fixable; infine retagga/pusha la stessa immagine solo sugli eventi di pubblicazione.

**Tech Stack:** GitHub Actions, Docker Buildx, Docker CLI, Trivy.

## Global Constraints

- Policy: availability-first approvata in `ignazio-ingenito/homelab#677`.
- Reporting: `HIGH,CRITICAL`, `ignore-unfixed: false`, `os,library`, `exit-code: 0`.
- Gate: `HIGH,CRITICAL`, `ignore-unfixed: true`, `os,library`, `exit-code: 1`.
- Invariante: `build once → verify exact artifact → publish exact artifact`.
- Preservare smoke test e Playwright Chromium reale.
- Preservare i tag `latest`, `sha-${GITHUB_SHA}` e `v*` già esposti.
- Non modificare il deployment GitOps `:latest` in questo PR.
- Nessuna allowlist generica.
- Nessun merge automatico.

---

### Task 1: rendere la pipeline single-build e availability-first

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `Dockerfile`, `scripts/smoke-test.sh`, `scripts/test-playwright-runtime.sh` già presenti nell'immagine.
- Produces: `/tmp/developer-workspace.tar` e immagine locale `developer-workspace:sha-${GITHUB_SHA}` usata da tutti i test, gli scan e il publish.

- [ ] **Step 1: verificare il contratto precedente**

Confermare nel workflow corrente che esistano tre invocazioni potenziali di `docker/build-push-action`: una per build/test, una per publish su `main` e una per publish dei tag. Questo è il comportamento da eliminare.

- [ ] **Step 2: sostituire il build con un export dell'artifact esatto**

Configurare una sola invocazione di `docker/build-push-action` con:

```yaml
platforms: linux/amd64
push: false
tags: developer-workspace:sha-${{ github.sha }}
labels: |
  org.opencontainers.image.revision=${{ github.sha }}
outputs: type=docker,dest=/tmp/developer-workspace.tar
cache-from: type=gha
cache-to: type=gha,mode=max
```

- [ ] **Step 3: caricare l'artifact e usare lo stesso tag per i test**

Aggiungere:

```bash
docker load --input /tmp/developer-workspace.tar
```

Eseguire smoke test e Playwright contro:

```text
developer-workspace:sha-${GITHUB_SHA}
```

- [ ] **Step 4: aggiungere il report Trivy completo non bloccante**

Usare:

```yaml
uses: aquasecurity/trivy-action@v0.36.0
with:
  image-ref: developer-workspace:sha-${{ github.sha }}
  format: table
  severity: HIGH,CRITICAL
  ignore-unfixed: false
  vuln-type: os,library
  scanners: vuln
  version: v0.69.3
  exit-code: '0'
```

Questo passaggio mantiene visibili anche le CVE senza fix.

- [ ] **Step 5: aggiungere il gate Trivy fixable bloccante**

Usare una seconda scansione dello stesso artifact:

```yaml
uses: aquasecurity/trivy-action@v0.36.0
with:
  image-ref: developer-workspace:sha-${{ github.sha }}
  format: table
  severity: HIGH,CRITICAL
  ignore-unfixed: true
  vuln-type: os,library
  scanners: vuln
  version: v0.69.3
  exit-code: '1'
```

- [ ] **Step 6: verificare l'identità dell'artifact prima del publish**

Controllare la label:

```bash
test "$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "developer-workspace:sha-${GITHUB_SHA}")" = "$GITHUB_SHA"
```

- [ ] **Step 7: pubblicare senza rebuild**

Su `main`, retaggare e pushare la stessa immagine come:

```text
ghcr.io/${repository_owner}/developer-workspace:latest
ghcr.io/${repository_owner}/developer-workspace:sha-${GITHUB_SHA}
```

Su tag `v*`, retaggare e pushare la stessa immagine come:

```text
ghcr.io/${repository_owner}/developer-workspace:${GITHUB_REF_NAME}
```

Non deve esistere alcun secondo build dedicato al publish.

- [ ] **Step 8: verifica statica**

Il workflow finale deve soddisfare contemporaneamente:

```text
count(docker/build-push-action) == 1
count(aquasecurity/trivy-action) == 2
contains(ignore-unfixed: false)
contains(exit-code: '0')
contains(ignore-unfixed: true)
contains(exit-code: '1')
contains(severity: HIGH,CRITICAL)
contains(outputs: type=docker,dest=/tmp/developer-workspace.tar)
contains(docker load --input /tmp/developer-workspace.tar)
contains(org.opencontainers.image.revision)
```

- [ ] **Step 9: verifica reale tramite PR**

Aprire un PR verso `main` e verificare il run GitHub Actions. Devono essere eseguiti:

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

Su PR non deve avvenire alcun push a GHCR.

- [ ] **Step 10: commit**

Commit previsto:

```text
ci: scan and publish exact workspace image artifact
```

### Task 2: verificare l'integrazione post-merge

Questa task non viene eseguita senza merge esplicitamente richiesto.

- [ ] Dopo merge verificare il run naturale `main`.
- [ ] Verificare che `latest` e `sha-${GITHUB_SHA}` puntino all'artifact validato.
- [ ] Verificare replica e scan Harbor.
- [ ] Verificare che CVE senza fix non blocchino il workload secondo la policy #677.
- [ ] Verificare `developer-workspace-0` Ready e Playwright Chromium funzionante.
