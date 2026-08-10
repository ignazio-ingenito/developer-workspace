# Developer Workspace — design CI availability-first

## Obiettivo

Allineare la pipeline dell'immagine `developer-workspace` alla policy availability-first approvata in `ignazio-ingenito/homelab#677`.

La pipeline deve:

- costruire l'immagine una sola volta;
- eseguire smoke test, Playwright e Trivy sullo stesso artifact;
- rendere visibili tutte le `HIGH` e `CRITICAL`;
- bloccare `HIGH` e `CRITICAL` solo quando esiste un fix disponibile;
- pubblicare esattamente l'artifact già verificato;
- non esporre credenziali di package write a codice eseguito durante la verifica di una PR;
- non cambiare in questa Wave il riferimento GitOps `:latest`.

## Scelta tecnica

Usare due job con separazione di privilegi:

1. `verify`: build, test e scan con soli permessi `contents: read`;
2. `publish`: solo su push a `main` o tag `v*`, con `packages: write`.

`verify` esporta l'immagine come `/tmp/developer-workspace.tar`, la carica nel daemon Docker e usa lo stesso artifact per smoke test, Playwright e due passaggi Trivy. Solo sugli eventi di pubblicazione il tar verificato viene conservato per un giorno e trasferito al job `publish`, che lo carica, ricontrolla la revision label e lo pusha senza rebuild.

Flusso:

```text
verify (read-only)
checkout
→ build una volta in /tmp/developer-workspace.tar
→ docker load
→ smoke test con MISE_GITHUB_TOKEN read-only
→ Playwright Chromium con MISE_GITHUB_TOKEN read-only
→ Trivy report HIGH/CRITICAL completo, non bloccante
→ Trivy gate HIGH/CRITICAL fixable, bloccante
→ verifica revision label
→ upload tar solo su push

publish (packages: write, solo push main/tag)
→ download tar verificato
→ docker load
→ verifica revision label
→ tag/push dello stesso artifact
```

## Perché questa scelta

Il primo run reale del PR ha mostrato che `workspace-tools bootstrap` usa `mise install` e può raggiungere il rate limit anonimo di GitHub. `mise` supporta `MISE_GITHUB_TOKEN`; il job `verify` usa quindi il token GitHub Actions con soli permessi read-only.

Separare `publish` evita di passare a codice costruito da una PR un token che abbia anche `packages: write`.

Non servono registry temporanei, PAT, nuovi secret o nuovi runner.

## Trivy: reporting e gate

### Report completo

Mostra anche le vulnerabilità senza fix ma non blocca:

```yaml
severity: HIGH,CRITICAL
ignore-unfixed: false
vuln-type: os,library
scanners: vuln
exit-code: '0'
```

### Gate fixable

Blocca solo le vulnerabilità correggibili:

```yaml
severity: HIGH,CRITICAL
ignore-unfixed: true
vuln-type: os,library
scanners: vuln
exit-code: '1'
```

Entrambi i passaggi usano la stessa immagine caricata dal tar. Non vengono introdotte allowlist generiche.

## Integrità dell'artifact

Il build applica:

```text
org.opencontainers.image.revision=${GITHUB_SHA}
```

La label viene verificata sia nel job `verify` sia, prima del push, nel job `publish`.

Il contratto è:

```text
workflow SHA verificato = artifact testato = artifact scansionato = artifact pubblicato
```

Su una pull request `GITHUB_SHA` è il merge commit temporaneo usato da GitHub Actions; su `main` e sui tag è il commit effettivamente pubblicato.

## Tagging

Il comportamento pubblico resta invariato:

- push su `main`: `latest` e `sha-${GITHUB_SHA}`;
- push tag `v*`: `${GITHUB_REF_NAME}`.

La migrazione del deployment GitOps da `:latest` a tag/digest immutabile resta fuori scope per questo PR.

## Verifica

1. run PR: build, load, smoke, Playwright e i due passaggi Trivy;
2. su PR il job `publish` deve essere skipped;
3. una sola `docker/build-push-action` nel workflow;
4. report unfixed non bloccante e gate fixable bloccante;
5. dopo merge, run naturale su `main` con trasferimento del tar e publish senza rebuild;
6. verifica successiva replica/scansione Harbor nella Wave #16.

## Fuori scope

- modifica della base image senza evidenza di CVE fixable che la richieda;
- Copa o patch binarie dell'immagine;
- modifica del deployment GitOps `:latest`;
- modifica generalizzata della policy Harbor per altri workload;
- merge automatico del PR.
