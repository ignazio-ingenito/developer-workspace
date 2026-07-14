# SSH agent personale

La gestione dello `ssh-agent` non appartiene a questo repository. E' una
configurazione personale del developer workspace e deve essere gestita dal
repository chezmoi dell'utente.

## Fonte autorevole

Individuare sempre il sorgente chezmoi con:

```bash
chezmoi source-path
```

Nel workspace corrente il file applicato deve essere:

```text
$HOME/.local/libexec/workspace-ssh-agent
```

La convenzione chezmoi prevista per renderlo eseguibile e':

```text
dot_local/libexec/executable_workspace-ssh-agent
```

Non copiare lo script in repository di progetto o in questo repository. Alla
fine deve esistere una sola fonte autorevole: il file sorgente gestito da
chezmoi.

## Inizializzazione Bash

Il file `.bashrc` gestito da chezmoi deve usare il file applicato, non un path
in `/workspaces`:

```bash
# Keep a single shared SSH agent across interactive shells and tmux windows.
if [[ -x "$HOME/.local/libexec/workspace-ssh-agent" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.local/libexec/workspace-ssh-agent"
  workspace_ensure_ssh_agent
fi
```

## Comportamento atteso

Lo script personale deve preservare questi comportamenti:

- socket condiviso in `~/.ssh/agent/socket`;
- riuso dello stesso agent tra shell interattive e finestre tmux;
- agent vivo ma senza chiavi trattato come stato valido;
- riparazione di socket, PID e lock stantii;
- lock per evitare concorrenza tra shell avviate insieme;
- assenza di agent duplicati sul socket condiviso;
- cleanup con `rm -f --`, mai `rm -rf`;
- nessuna cache automatica della passphrase.

Per tmux, aggiornare sia l'ambiente globale sia quello della sessione corrente,
cosi' anche le nuove finestre ereditano `SSH_AUTH_SOCK`.

## Verifica

Dopo modifiche chezmoi:

```bash
chezmoi apply
test -x "$HOME/.local/libexec/workspace-ssh-agent"
bash -n "$HOME/.local/libexec/workspace-ssh-agent"
shellcheck "$HOME/.local/libexec/workspace-ssh-agent"
grep -n '/workspaces' "$HOME/.bashrc"
grep -RIn --exclude-dir=.git '/workspaces/iwant/scripts/workspace-ssh-agent.sh' \
  "$HOME" /workspaces 2>/dev/null
bash -ic 'echo "$SSH_AUTH_SOCK"; ssh-add -l; pgrep -af "^ssh-agent -a"'
tmux show-environment -g SSH_AUTH_SOCK
```

`ssh-add -l` puo' stampare:

```text
The agent has no identities.
```

Questo significa che l'agent e' raggiungibile ma non contiene chiavi caricate.
Non e' un errore di bootstrap.

## Dopo la ricreazione del Pod

La configurazione chezmoi ricrea lo script e il socket condiviso al primo avvio
di una shell interattiva. Lo sblocco della chiave resta manuale:

```bash
ssh-add
```

Inserire la passphrase quando richiesta. Il workspace non deve salvare o
automatizzare la passphrase.
