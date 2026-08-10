# Developer Workspace — design CI availability-first

## Obiettivo

Allineare la pipeline dell'immagine `developer-workspace` alla policy availability-first approvata in `ignazio-ingenito/homelab#677`.

La pipeline deve:

- costruire l'immagine una sola volta;
- eseguire smoke test, Playwright e Trivy sullo stesso artifact;
- bloccare `HIGH` e `CRITICAL` solo quando esiste un fix disponibile;
- pubblicare esattamente l'artifact già verificato;
- non cambiare in questa Wave il riferimento GitOps `:latest`.

## Scelta tecnica

Usare un singolo job GitHub Actions.

Il build esporta l'immagine come tar OCI/Docker locale. Il job carica quel tar nel daemon Docker, esegue i test e lo scan Trivy, poi — solo su `main` o tag `v*` — retagga e pusha la stessa immagine.

Flusso:

```text
checkout
→ build una volta in /tmp/developer-workspace.tar
→ docker load
→ smoke test
→ Playwright Chromium
→ Trivy HIGH/CRITICAL, ignore-unfixed=true
→ verifica revision label
→ tag/push dello stesso artifact
```

## Perché questa scelta

È il delta minimo rispetto alla pipeline attuale e rimuove il problema principale: oggi l'immagine testata viene ricostruita prima del publish.

Non servono:

- registry temporanei;
- job aggiuntivi;
- upload/download artifact tra job;
- nuovi secret;
- nuovi runner.

## Gate Trivy

Configurazione target:

```yaml
severity: HIGH,CRITICAL
ignore-unfixed: true
vuln-type: os,library
scanners: vuln
exit-code: '1'
```

Le vulnerabilità senza fix restano nel reporting dello scanner ma non bloccano la delivery.

Non vengono introdotte allowlist generiche.

## Integrità dell'artifact

Il build applica la label OCI:

```text
org.opencontainers.image.revision=${GITHUB_SHA}
```

Prima del push la pipeline verifica che l'immagine caricata dal tar contenga la stessa revision.

Questo rende esplicito il contratto:

```text
commit sorgente = artifact testato = artifact scansionato = artifact pubblicato
```

## Tagging

Il comportamento pubblico resta invariato:

- push su `main`:
  - `latest`
  - `sha-${GITHUB_SHA}`
- push tag `v*`:
  - `${GITHUB_REF_NAME}`

La migrazione del deployment GitOps da `:latest` a tag/digest immutabile è fuori scope per questo PR e verrà valutata separatamente.

## Verifica

La modifica è configurazione CI, non codice applicativo. La verifica richiesta è:

1. validazione sintattica del workflow;
2. run PR con build, smoke, Playwright e Trivy verdi;
3. conferma che non esista un secondo `docker/build-push-action` per il publish;
4. dopo merge, run naturale su `main` che pubblica i tag previsti dallo stesso artifact verificato;
5. verifica successiva di replica/scansione Harbor nella Wave #16.

## Fuori scope

- modifica della base image senza evidenza di CVE fixable che la richieda;
- Copa o patch binarie dell'immagine;
- modifica del deployment GitOps `:latest`;
- modifica generalizzata della policy Harbor per altri workload;
- merge automatico del PR.
