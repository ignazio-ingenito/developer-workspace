# Operator bootstrap and recovery

This runbook supports the acceptance workflow for
`ignazio-ingenito/homelab#300`. Run the commands inside the Developer
Workspace. Interactive credentials and private keys stay in the persistent
home; none belongs in the image or Git.

## 1. Migrate the existing shell baseline

The first image wrote an Oh My Bash configuration that referenced modules not
present in the pinned installation. Existing PVCs retain that file by design.

Inspect before replacing it:

```bash
cp ~/.bashrc ~/.bashrc.before-workspace-300
diff -u ~/.bashrc /opt/developer-workspace/bashrc || true
install -m 0644 /opt/developer-workspace/bashrc ~/.bashrc
exec bash
workspace-doctor
```

The corrected baseline loads the real `git` plugin, activates `mise` directly,
and does not request the nonexistent `plugin:mise` or `alias:git` modules.

## 2. Create and use the private dotfiles repository

Create a private repository named `dotfiles` in GitHub. Do not initialize it
with secrets, an SSH private key, an age private key, Codex state, Bitwarden
state, or GitHub tokens.

Create the private repository without a README, license, or other initial file.
After Git SSH is working, populate it from the existing workspace:

```bash
chezmoi init git@github.com:ignazio-ingenito/dotfiles.git
chezmoi add ~/.bashrc ~/.tmux.conf
source_dir=$(chezmoi source-path)
git -C "$source_dir" add .
git -C "$source_dir" commit -m "feat(dotfiles): bootstrap developer workspace"
git -C "$source_dir" push -u origin main
```

Verify the reproducible bootstrap from a clean test home before relying on it:

```bash
test_home=$(mktemp -d)
HOME="$test_home" chezmoi init git@github.com:ignazio-ingenito/dotfiles.git
HOME="$test_home" chezmoi diff
HOME="$test_home" chezmoi apply --dry-run --verbose
rm -rf "$test_home"
```

On the persistent home, review and apply explicitly:

```bash
chezmoi diff
chezmoi apply --dry-run --verbose
chezmoi apply --verbose
```

On later logins:

```bash
chezmoi update --dry-run
chezmoi diff
chezmoi apply
```

Startup never runs `chezmoi apply`.

Recommended tracked files are `.bashrc`, `.tmux.conf`, `.gitconfig`, and small
non-secret CLI preferences. Keep these paths out of the dotfiles repository:

```text
~/.ssh/id_*
~/.config/sops/age/keys.txt
~/.config/gh/hosts.yml
~/.codex/
~/.config/Bitwarden CLI/
```

## 3. Git over SSH and GitHub CLI

Create one passphrase-protected key dedicated to this workstation:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519_developer_workspace \
  -C "developer-workspace@skunklabs.uk"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_developer_workspace
cat ~/.ssh/id_ed25519_developer_workspace.pub
```

Add only the public key to GitHub, then verify:

```bash
ssh -T git@github.com
gh auth login --hostname github.com --git-protocol ssh --web
gh auth status
gh issue view 300 --repo ignazio-ingenito/homelab
```

Create pull requests with an explicit branch and Conventional Commit messages.
Do not enable auto-merge.

## 4. Codex CLI

Codex is installed as a standalone tool in the persistent home. mise owns the
rest of the home tool baseline directly.

```bash
mise ls
mise doctor
mise install
mise upgrade
codex update
hash -r
command -v codex
codex --version
```

`command -v codex` must return `/usr/local/bin/codex`. The Codex launcher
keeps the last usable binary when an update fails and archives a historical
npm-managed shim only after the standalone installation succeeds.

Authenticate interactively from a tmux session:

```bash
work codex-login
codex login
codex
```

The home directory is persistent, so the installation and Codex state survive
Pod recreation. Never copy Codex state into the image or dotfiles. See
`docs/TOOL-LIFECYCLE.md` for ownership and update rules.

## 5. Vaultwarden CLI

The image fixes `BW_SERVER` to `https://vault.skunklabs.uk`:

```bash
bw config server https://vault.skunklabs.uk
bw login
export BW_SESSION="$(bw unlock --raw)"
bw sync
bw status
```

Login state persists below `~/.config/Bitwarden CLI`. `BW_SESSION` is an
in-memory shell value: unlock again after a new shell or Pod. Do not put the
master password or session value in shell history, dotfiles, or Kubernetes.

## 6. SOPS and age

The repository is encrypted to the age recipient declared in the root
`.sops.yaml`. Retrieve the existing matching identity from Vaultwarden or the
approved recovery backup; generating an unrelated key will not decrypt the
existing manifests. Store the identity at `~/.config/sops/age/keys.txt` with
mode `600` and never commit it.

```bash
install -d -m 0700 ~/.config/sops/age
# Retrieve the existing identity without printing it to the terminal.
# Replace the placeholder with the approved Vaultwarden item name or ID.
umask 077
bw get notes '<homelab SOPS age identity>' \
  > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt
```

The derived public recipient must be exactly:

```text
age1nrxrxedv7ersz0jhawgljcnxhjmgxzkkdh5pdzj0f8c2yern0u0qahp5tu
```

Stop if it differs. Adding or rotating recipients requires a separate reviewed
change to `homelab`; it is not part of this bootstrap.

Use an approved encrypted manifest from `homelab` for the acceptance test:

```bash
sops --decrypt path/to/approved.enc.yaml >/dev/null
sops path/to/approved.enc.yaml
git diff --check
```

Confirm the tracked file still contains a top-level `sops:` block and no
plaintext secret value before committing.

## 7. mise project toolchains

In a disposable test repository:

```bash
mkdir -p /workspaces/mise-acceptance && cd /workspaces/mise-acceptance
git init
mise use python@3.13
mise install
mise exec -- python --version
git add mise.toml
git commit -m "chore: declare project toolchain"
```

Language versions belong in each project, not in the workspace image.

## 8. tmux and Safari recovery

`work` attaches to the default `work` session. A named session is equally
simple:

```bash
work acceptance
sleep 3600
```

Suspend Safari or disconnect the network, reconnect to code-server, open a new
terminal, and run:

```bash
work acceptance
```

The original process must still be running. Detach with `Ctrl-b d`; list
sessions with `tmux ls`.

## 9. Extension and Pod persistence test

Install one non-baseline extension from code-server, record the list, recreate
the Pod through the approved operator path, then compare:

```bash
code-server --extensions-dir ~/.local/share/code-server/extensions \
  --list-extensions | sort > /tmp/extensions.before
```

After recreation:

```bash
code-server --extensions-dir ~/.local/share/code-server/extensions \
  --list-extensions | sort > /tmp/extensions.after
diff -u /tmp/extensions.before /tmp/extensions.after
workspace-doctor
```

Also verify Git SSH, `gh auth status`, Codex login state, Vaultwarden login
state, and SOPS decryption. A Vaultwarden unlock and `ssh-add` may be required
again; that is intentional and avoids storing unlock secrets.
