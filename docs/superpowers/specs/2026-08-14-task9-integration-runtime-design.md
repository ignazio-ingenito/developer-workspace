# Task 9 — Integration runtime design

**Status:** Active  
**Date:** 2026-08-14  
**Mission:** `ignazio-ingenito/developer-workspace#33` — Task 9 Integration runtime  
**RFC:** RFC-0001 v0.1.6

## Obiettivo

Ridurre l'orchestration custom dei test/runtime integration mantenendo soltanto i test che proteggono failure applicativi reali.

La regola di scelta è:

`DELETE / non introdurre > capability nativa > tool standard/OSS > custom`

Testcontainers non è uno standard da imporre trasversalmente: viene usato soltanto quando possiede responsabilità che la capability nativa disponibile non copre con la stessa semplicità.

## Fatti verificati

### Aeris

- Il failure reale da proteggere è la regressione di una migration storica/RLS: il pilota deve poter accedere e modificare il velivolo collegato e non deve poter accedere o modificare un velivolo estraneo.
- `aeris#248` ha dimostrato che questo contratto può essere espresso come un singolo test Node/`pg` e che il vecchio Bash, il wrapper `psql`, la porta fissa, l'autenticazione `trust`, il workflow `Runtime Migrations` duplicato e i test statici della forma dell'orchestrazione possono essere eliminati.
- Il pilot `@testcontainers/postgresql` sulla PR #248 è tecnicamente funzionante sul runner `ci-container`.
- GitHub Actions `services` possiede già nativamente il lifecycle di un singolo PostgreSQL necessario da Aeris.

### iWant

- `scripts/run-schema-migrator-test.sh` orchestra manualmente lifecycle PostgreSQL, readiness, porte e cleanup ma protegge failure reali del migrator: credenziali superuser vietate, idempotenza, concorrenza, schema finale e checksum drift.
- `scripts/run-piloti-runtime-test.sh` orchestra PostgreSQL e PostgREST in sequenza e verifica un percorso reale applicazione/PostgREST/PostgreSQL più audit e authorization.
- La parte di dominio dei test deve restare; il glue Docker non ha ownership applicativa propria.
- Il progetto è Go e non usa oggi Testcontainers.

### n8n

- Il current importer Homelab usa `export -> import -> publish` e dipende dallo stato live per ripristinare lo stato published persistito.
- Le fonti Active sono state riallineate prima di questo design.
- La disponibilità effettiva di n8n Source Control dipende dall'entitlement corrente del runtime e non è ancora verificata.
- Nessuna decisione di implementazione n8n deve assumere tale entitlement.

## Decisione approvata

### 1. Aeris — GitHub Actions service + test Node/pg

Aeris non manterrà Testcontainers come dependency steady-state per questo contratto.

Il target è:

1. un solo workflow `Controlled Runtime`;
2. PostgreSQL avviato tramite `services: postgres` di GitHub Actions;
3. credenziali esplicite non-`trust` e database isolato per il test;
4. un solo test Node che usa `pg` direttamente e preserva lo scenario historical-upgrade/RLS;
5. nessun wrapper `psql`, nessuna shell di orchestration, nessuna porta discovery custom, nessun secondo workflow migration;
6. nessun test statico della forma YAML/shell.

Il test deve dipendere soltanto dalla connection string fornita dal workflow, non da dettagli del container GitHub service.

### 2. iWant — Testcontainers for Go, limitato al lifecycle integration

Testcontainers è giustificato in iWant perché il test runtime non richiede soltanto un PostgreSQL isolato: deve costruire un ambiente sequenziale con almeno PostgreSQL e PostgREST, con setup/migration tra i due e connection data dinamici.

Il target è:

- Testcontainers for Go possiede start/stop, networking, readiness e connection data dei container di test;
- il test applicativo possiede fixture, migration, assertion, authorization e audit;
- nessun framework/wrapper interno viene creato sopra Testcontainers;
- niente astrazione comune Aeris/iWant: i linguaggi e i failure mode sono diversi e una libreria condivisa sarebbe nuovo custom senza beneficio dimostrato;
- i container restano test-only e il runtime prodotto non cambia.

Per `run-schema-migrator-test.sh`, la conversione a Testcontainers è ammessa solo se riduce effettivamente glue e mantiene leggibili i test di superuser rejection, idempotenza, concurrent apply e checksum drift. Se il test diventa più complesso del Bash che rimuove, il target deve essere riesaminato prima di procedere.

Per `run-piloti-runtime-test.sh`, Testcontainers è il candidato principale perché sostituisce direttamente network/container/readiness/port/cleanup custom mantenendo invariato il contratto browser/API/PostgREST/PostgreSQL.

### 3. n8n — decisione separata dopo verifica entitlement

Nessuna modifica al runtime importer n8n viene inclusa nelle tranche Aeris/iWant.

Prima di scegliere il target n8n occorre verificare sul runtime corrente l'entitlement/licensing per Source Control. La verifica deve essere read-only.

Dopo il fatto verificato:

- se Source Control nativo è disponibile e copre il workflow Git -> runtime richiesto, parte come candidato preferito;
- se non è disponibile, si confrontano Server CLI/Public API/`@n8n/cli` contro il failure reale e il requisito Git one-way source of truth;
- non si preserva l'hidden live state solo perché esiste oggi;
- non si introduce queue/multi-main soltanto per ottenere un flag CLI.

## Alternative scartate

### Testcontainers sia su Aeris sia su iWant

**Pro:** uniformità concettuale e lifecycle test-local.  
**Contro:** Aeris introdurrebbe un framework e una catena di dipendenze per un solo PostgreSQL già posseduto da GitHub Actions.  
**Decisione:** scartata per RFC-0001 §1 e §7.

### GitHub Actions services sia su Aeris sia su iWant

**Pro:** minimo numero di dependency test.  
**Contro:** iWant conserverebbe orchestration custom per PostgREST e per la sequenza setup -> servizio -> test, quindi eliminerebbe solo una parte del problema.  
**Decisione:** scartata come soluzione trasversale.

### Framework integration comune tra repository

**Pro:** possibile uniformità di naming e lifecycle.  
**Contro:** nuovo custom cross-repo, linguaggi diversi, failure mode diversi, nessun consumer che richieda un contratto comune.  
**Decisione:** DELETE / non introdurre.

## Flusso operativo risultante

### Aeris

PR -> `Controlled Runtime` -> GitHub service PostgreSQL healthy -> test Node/`pg` -> PASS/FAIL.

Il debugging usa log del test e log del service GitHub quando disponibili. Non esistono più log artifact custom obbligatori né wrapper da diagnosticare.

### iWant

PR -> workflow `ci-container` -> test Go -> Testcontainers crea PostgreSQL/PostgREST necessari -> fixture/migration -> assertion -> cleanup automatico.

Il debugging deve usare errori del test e log container solo quando utili al failure corrente. Nessuna evidence artifact permanente senza consumer.

### n8n

Task 9 resta sequenziale: prima licensing reality check, poi scelta del meccanismo Git-to-runtime. Nessuna implementazione in parallelo finché manca il fatto che determina l'alternativa minima.

## Impatto

### PR e CI

- Aeris: meno workflow e meno dependency di test rispetto al pilot #248; resta `ci-container` perché GitHub service PostgreSQL richiede Docker sul runner corrente.
- iWant: resta `ci-container`; i test Go diventano owner anche del lifecycle effimero necessario.
- n8n: nessun cambiamento finché il reality check non è chiuso.

### Troubleshooting

- Aeris: connection failure -> service/runner; assertion failure -> migration/RLS.
- iWant: container lifecycle failure -> Testcontainers/runtime Docker; assertion failure -> dominio/migration/PostgREST.
- evitare retry CI come diagnosi; usare log esistenti e verifiche locali/proporzionali secondo RFC §8.

### Rollback

- Aeris: revert della PR Task 9 ripristina il precedente gate; nessun dato persistente coinvolto.
- iWant: revert della PR Task 9 ripristina gli script; nessun cambiamento al runtime prodotto.
- n8n: non applicabile finché non esiste una modifica.

### Secret/tool/config

- Aeris: nessun nuovo secret; nessuna dependency Testcontainers steady-state.
- iWant: nuova dependency Go Testcontainers; nessun secret runtime aggiuntivo; Docker socket già richiesto dal runner `ci-container`.
- n8n: eventuali API key/entitlement restano parte della decisione successiva e non sono autorizzati da questo design.

## Failure mode protetti

### KEEP

- Aeris historical-upgrade/RLS authorization regression.
- iWant migrator superuser rejection, idempotenza, concurrency, checksum drift e target schema.
- iWant browser/API/PostgREST/PostgreSQL authorization/audit path.

### DELETE

- Bash che esiste soltanto per start/wait/port/cleanup container quando un owner standard lo sostituisce.
- wrapper `psql` e parsing URI custom.
- test della forma YAML/shell o della presenza di specifiche stringhe di orchestration.
- workflow duplicati che esercitano lo stesso failure senza failure mode distinto.

## Sequenza di implementazione

1. Riallineare `aeris#248` al design approvato, mantenendo il test Node ma sostituendo Testcontainers con GitHub `services: postgres`.
2. Verificare il current head Aeris senza rerun manuali; usare il run naturale prodotto dal nuovo commit e fermarsi su failure pre-step/infrastrutturali.
3. Eseguire il reality check dettagliato iWant sul current `main`, tenendo conto delle PR aperte che possono modificare lo stesso perimetro.
4. Implementare la minima conversione iWant a Testcontainers for Go soltanto dopo aver definito esattamente i due contratti da preservare.
5. Verificare n8n entitlement in read-only e completare il design specifico n8n prima di modificarne il runtime.

## Criteri di chiusura Task 9

Task 9 è chiudibile quando:

- Aeris non contiene orchestration PostgreSQL custom né Testcontainers non necessario, e il failure RLS reale resta protetto;
- iWant non contiene lifecycle Docker shell custom per i gate integration in scope, salvo eventuali eccezioni che abbiano superato esplicitamente il burden of proof;
- n8n ha un owner Git-to-runtime deterministico deciso sulla base dell'entitlement verificato oppure un DEFER esplicito con blocker esterno reale;
- documentazione Active dei repository coinvolti rappresenta lo stato risultante;
- nessun nuovo framework comune o governance CI è stato introdotto;
- nessun retry GitHub Actions è stato eseguito senza autorizzazione.

## Informazioni ancora mancanti

- entitlement/licensing effettivo dell'istanza n8n per Source Control;
- interazioni concrete tra Task 9 iWant e le PR aperte sul medesimo repository, da verificare prima di creare una branch operativa.

Queste informazioni non bloccano l'allineamento di Aeris; bloccano soltanto le rispettive tranche n8n/iWant quando diventano necessarie.
