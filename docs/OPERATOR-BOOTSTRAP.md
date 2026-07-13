# Operator bootstrap and recovery

This runbook completes `ignazio-ingenito/homelab#300`. Run the commands inside
the Developer Workspace. Interactive credentials and private keys stay in the
persistent home; none belongs in the image or Git.

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

After Git SSH is working:

```bash
chezmoi init git@github.com:ignazio-ingenito/dotfiles.git
chezmoi diff
# Review every path. Applying is always explicit.
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

Authenticate interactively from a tmux session:

```bash
work codex-login
codex login
codex
```

The home directory is persistent, so Codex state survives Pod recreation. Never
copy its state into the image or dotfiles.

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

Store the workstation age identity at
`~/.config/sops/age/keys.txt` with mode `600`. Keep a recovery copy in
Vaultwarden; never commit the private identity.

```bash
install -d -m 0700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt
```

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
