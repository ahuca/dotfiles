# dotfiles — Ubuntu and Windows workstations

Three layers, one repo:

- **`linux/`** is an Ansible project that provisions this Ubuntu workstation against itself: apt repos
  and packages, GNOME, udev, systemd, TPM, VMware — anything machine-wide.
  Nothing here talks to a remote host: the inventory is `localhost` with
  `ansible_connection=local`.
- **`windows/`** is the Windows counterpart, a WinGet configuration: packages and
  the few machine-wide settings, applied with `winget configure`.
- **`home/`** holds the dotfiles for both, applied with
  [chezmoi](https://www.chezmoi.io/): git and its per-remote profiles, SSH,
  delta and lazygit, Neovim (LazyVim), zsh / PowerShell, Ghostty / Windows
  Terminal, and the Vaultwarden secrets plumbing. Templates pick the right
  variant per OS.

```
bootstrap.sh          Linux: installs Ansible, runs site.yml, then chezmoi
bootstrap.ps1         Windows: winget configure, then chezmoi
.chezmoiroot          tells chezmoi its source state is home/
home/                 the dotfiles (chezmoi source state; see below)
windows/
  configuration.winget  Windows packages and machine-wide settings
linux/                the Ansible project
  site.yml            default entry point -> playbooks/workstation.yml
  inventory.ini       localhost, local connection
  group_vars/all.yml  ALL the configuration (package lists, repos, hotkeys, ...)
  playbooks/
    workstation.yml   everyday setup: repos, packages, desktop, shell, node, brew
    tpm-unlock.yml    bind the LUKS root volume to the TPM2 (clevis)
    vmware.yml        VMware Workstation modules, MOK signing, temp dir, perms, hotkeys, scaling, clipboard
  roles/              one role per concern
```

## Quick start (Ubuntu)

Fresh machine, nothing cloned (the repo is public, so no credentials needed):

```bash
wget -qO- https://raw.githubusercontent.com/ahuca/dotfiles/main/bootstrap.sh | bash
```

It clones to `~/Projects/dotfiles`, provisions, applies the dotfiles with
chezmoi, then runs `rbw login` and `sync-secrets`. You type your sudo password
once (bootstrap checks it, then reuses it for its own `sudo` calls and hands it
to Ansible through a pipe as the become password) and your Vaultwarden master
password. On a machine's first run chezmoi also asks, once, for the few
personal values this repo deliberately doesn't hold — see
[Per-machine values](#per-machine-values). Press Enter at the Vaultwarden URL
prompt to skip secrets entirely. For Windows, see [Windows](#windows).

From an existing checkout:

```bash
./bootstrap.sh
```

### Ansible version

`bootstrap.sh` installs the **latest upstream `ansible-core`** with pipx into
`~/.local/bin`, because Ubuntu's archive trails upstream (resolute ships
ansible-core 2.20.1 against 2.21.4 upstream). Collections come from
`linux/requirements.yml` rather than the distro bundle.

To use the distro package instead:

```bash
ANSIBLE_SOURCE=apt ./bootstrap.sh
```

If you already installed Ansible from apt, `~/.local/bin` wins on `PATH` and
bootstrap will point that out; `sudo apt-get purge ansible ansible-core` drops
the duplicate.

Note `ansible.cfg` sets `stdout_callback = ansible.builtin.default` with
`callback_result_format = yaml`, **not** `stdout_callback = yaml` — the latter
resolves to `community.general.yaml`, which was removed in community.general
12.0.0.

After Ansible is installed you can drive it directly:

```bash
cd linux
ansible-playbook site.yml -K                 # everything
ansible-playbook site.yml -K --check         # dry run
ansible-playbook site.yml -K --tags packages # just the package installs
ansible-playbook site.yml -K --tags copyq    # just the CopyQ hotkey
ansible-playbook site.yml -K --tags kdeconnect  # just the KDE Connect ufw rule + XWayland clipboard fix
ansible-playbook site.yml -K --tags topgrade  # just topgrade (.deb from its GitHub release)
ansible-playbook site.yml --tags extensions  # just the GNOME Shell extensions (Tiling Shell)
ansible-playbook site.yml -K --tags touchpad  # just the touchpad middle-button fix
ansible-playbook site.yml --tags zsh_plugins  # just the oh-my-zsh plugins
ansible-playbook site.yml -K --tags docker   # just Docker Engine (and its repo)
ansible-playbook site.yml -K --skip-tags docker  # everything except Docker
```

`-K` prompts for the sudo password; drop it only if you have genuinely
passwordless (`NOPASSWD`) sudo. A warm sudo timestamp is not enough — Ansible's
become runs without a tty, and sudo-rs rejects a cached ticket there.

`bootstrap.sh` applies the dotfiles only after a whole workstation run (no
`--tags`); with `--check` it shows `chezmoi diff` instead. Otherwise run
chezmoi yourself — see [Dotfiles](#dotfiles-home-via-chezmoi).

## What `workstation.yml` sets up

Preference throughout: **package managers only** — apt repo > snap > apt-installed `.deb`.

| Role       | What it does                                                                 |
|------------|------------------------------------------------------------------------------|
| `common`   | apt keyring dir, base tooling (curl, wget, git, gpg, …)                       |
| `apt_repos`| signing keys + deb822 `.sources` for Charm, VS Code, GitHub CLI, Claude Code, Edge, Microsoft prod (Intune), ONLYOFFICE |
| `packages` | apt packages (incl. KDE Connect + its ufw ports + XWayland start for clipboard sync, lazygit, delta, tldr via tealdeer + its pages, rbw + pinentry for `sync-secrets`, ONLYOFFICE Desktop Editors), snaps (Bitwarden, PowerShell), D2, topgrade, UniFi Identity Desktop |
| `docker`   | Docker's apt repo + Docker Engine, Buildx, Compose; you in the `docker` group |
| `desktop`  | CopyQ GNOME hotkey (Wayland-safe) + autostart; Super+Ctrl+T for "Always on top" (`wm_toggle_above_bindings`); Ctrl+Alt+Space to switch the keyboard layout (`wm_switch_input_source_bindings`); opt-in `< > \|` on the key left of 1 (`xkb_lsgt_on_tlde`); GNOME Shell extensions from extensions.gnome.org (`gnome_extensions`: Tiling Shell, replacing Ubuntu's Tiling Assistant; loads at next login) |
| `touchpad` | ASUS ProArt Studiobook touchpad: a root service that forwards the physical middle button the kernel drops (only where that touchpad is present; see below) |
| `shell`    | oh-my-zsh and the plugins it doesn't bundle (fzf-tab, zsh-autosuggestions, zsh-syntax-highlighting); zsh as the login shell. `~/.zshrc` itself comes from chezmoi |
| `homebrew` | Linuxbrew + `opencode` (which pulls in ripgrep) + `chezmoi`                   |
| `nodejs`   | fnm + pnpm from Homebrew, latest LTS node as fnm's default; removes a leftover nvm (`~/.nvm`, its `~/.bashrc` lines, corepack's cache) |

#### Three notes on how packages are sourced

**Vendor-managed repos.** Once `code` and `microsoft-edge-stable` are
installed, those packages rewrite their own `.sources` file on every upgrade
(Edge's even carries "changes to this file will not be preserved"). The
`apt_repos` role therefore only registers those two while the package is
absent, so the first install can happen — after that it leaves them alone
instead of fighting the postinst and leaving two copies of the repo behind. It
also deletes one-line `.list` files for the same repos (as written by
hand-rolled setup scripts or vendor install guides), which would otherwise
duplicate them.

**PowerShell comes from the snap, not apt.** Microsoft's prod repo for
resolute (26.04) publishes `powershell-preview` (7.7.0-preview) but no stable
`powershell` package, so `apt install powershell` fails on this release. The
snap is the current stable route. The prod repo *is* registered, but only for
Intune Portal — and note it is signed with Microsoft's 2025 key
(`microsoft-2025.asc`), not the `microsoft.asc` used by the VS Code and Edge
repos.

**Homebrew without nested sudo.** The official `curl | bash` installer shells
out to `sudo` itself. Ansible runs tasks without a tty, so under sudo-rs
(Ubuntu's default since 25.10) that fails with *"interactive authentication is
required"* even when Ansible's own become works fine. The role instead creates
the prefix as root, hands it to you, and uses Homebrew's documented git-clone
install, which needs no privileges of its own.

Everything configurable lives in `linux/group_vars/all.yml` — add a package
to `apt_packages`, a repo to `apt_repositories`, and re-run.

To upgrade installed packages rather than just ensure they are present:

```bash
ansible-playbook site.yml -K -e package_state=latest
```

**Docker Engine, not Docker Desktop.** The `docker` role follows
[Docker's Ubuntu install guide](https://docs.docker.com/engine/install/ubuntu/):
Docker's own apt repo, `docker-ce` rather than Ubuntu's `docker.io`, and the
conflicting archive packages removed first. It is part of every run and
registers its own repo, so `--skip-tags docker` (or `docker_enabled: false`)
leaves Docker out entirely. Docker Desktop for Linux runs
containers inside a KVM VM; Engine runs them as ordinary host processes, so it
costs VMware guests nothing. Two things to know: membership of the `docker`
group is root-equivalent, and ports you publish with `-p` bypass ufw.

**Touchpad middle button.** On the ASUS ProArt Studiobook's three-button
touchpad (Elan `04F3:31AF`), the physical middle button does nothing: the
hardware sends it, but in a second Mouse collection whose buttons the kernel
drops as duplicates of the first one's. `libinput debug-events` (from `libinput-tools`)
shows no `BTN_MIDDLE`, and `/sys/kernel/debug/hid/<dev>/rdesc` shows that
collection's buttons mapped to `Sync.Report`. The `touchpad` role installs
`touchpad-middle-button@hidrawN.service`, started by a udev rule, which reads
the button from hidraw and presses it on a virtual mouse. Remove it once the
kernel maps the button itself.

### After the run

- Log out and back in for zsh to take effect, and for the `docker` group.
- Bitwarden: **Settings → Enable SSH agent**, unlock the vault, add SSH-key
  items. The socket only exists once the agent is on; `ssh-add -l` then lists
  your keys.
- Then `chezmoi apply` once more, so git finds the signing keys (see
  [Git profiles and signing](#git-profiles-and-signing)).

## Dotfiles: `home/` via chezmoi

Everything under `$HOME` comes from `home/`, chezmoi's source state
(`.chezmoiroot` points it there, so the rest of the repo is invisible to it).
Ansible installs software; chezmoi writes the configuration. Both bootstraps
run `chezmoi init --apply --source <checkout>`, which also records the
checkout as chezmoi's source directory, so afterwards:

```bash
chezmoi diff             # what apply would change
chezmoi apply            # write it
chezmoi edit ~/.zshrc    # edit the source file behind a target
chezmoi init --prompt    # answer the per-machine questions again
```

A target you edited by hand makes `chezmoi apply` stop and ask. Keep
machine-only additions in the local files the managed ones read:
`~/.gitconfig.local`, `~/.ssh/config.local`, `~/.zshrc.local`.

| Target | Linux | Windows |
|--------|:-----:|:-------:|
| `~/.gitconfig`, `~/.config/git/` — identity, SSH signing, per-remote profiles, delta | ✓ | ✓ |
| `~/.ssh/config`, `~/.ssh/git-profiles/*.pub` — one Bitwarden key per profile host | ✓ | ✓ |
| lazygit (delta as its pager) — `~/.config/lazygit/` / `%LOCALAPPDATA%\lazygit\` | ✓ | ✓ |
| `~/.config/opencode/opencode.jsonc` — keys by `{file:}` reference | ✓ | ✓ |
| Neovim's LazyVim config — `~/.config/nvim/` / `%LOCALAPPDATA%\nvim\` (see [Neovim](#neovim-lazyvim)) | ✓ | ✓ |
| `sync-secrets` — `~/.local/bin/sync-secrets` / `sync-secrets.ps1` | rbw | bw |
| `~/.config/powershell/profile.ps1` — history suggestions, menu Tab, Oh My Posh | ✓ | ✓ |
| `~/.zshrc`, rbw's config, Ghostty's config | ✓ | |
| Windows Terminal (PowerShell 7 default, CaskaydiaCove Nerd Font), the Nerd Font itself | | ✓ |

Templates branch on `.chezmoi.os`; `home/.chezmoiignore` drops what a
platform doesn't use. Shared pieces live in `home/.chezmoitemplates/`, and
repo data in `home/.chezmoidata/vault.yaml`: everything from the vault (the
secrets list, rbw's settings, the SSH agent socket) under one `vault` key,
merged with the per-machine `vault.url` / `vault.email`.

### Neovim (LazyVim)

`home/private_dot_config/nvim/` is the [LazyVim](https://www.lazyvim.org/)
config; on Windows each file under `home/AppData/Local/nvim/` is a one-line
stub that renders the same source as its Linux twin, so a new file there
needs a stub too. The first `nvim` clones lazy.nvim, then LazyVim and its
plugins; mason installs the LSP servers and tools it is missing (the
npm-based ones need node, so start it from a shell that loaded fnm). Add
servers in `lua/plugins/lsp.lua` rather than through `:Mason`, so every
machine gets them.

`lua/config/lazy.lua` imports the extras for what this repo holds: Ansible,
YAML (`.winget` files are YAML too, see `options.lua`), JSON, Markdown, TOML,
Python, and chezmoi. That last one highlights the templates here, through
`lua/plugins/chezmoi.lua`, which is rendered from
`home/.chezmoitemplates/nvim-chezmoi.lua` with the machine's source path
(the extra assumes `~/.local/share/chezmoi`). Templates get no LSP.

Two files stay out of the repo because Neovim rewrites them:
`lazy-lock.json` (plugin versions; `:Lazy update`, the update checker and
topgrade move it forward) and `lazyvim.json` (LazyVim's news and migration
state). That second one is also where `:LazyExtras` saves extras, so add an
extra as another import in `lazy.lua` instead.

### Per-machine values

Nothing identifying is in the repo. `chezmoi init` asks once for each value
below and stores the answer in `~/.config/chezmoi/chezmoi.toml`; each prompt
defaults to what the machine already knows, so on a machine the old Ansible
roles set up it only asks you to confirm. An empty answer turns that feature
off.

| Value | Default taken from |
|-------|--------------------|
| git `user.name` / `user.email` | `GIT_NAME` / `GIT_EMAIL`, else `git config --global` |
| Vaultwarden URL and login | `VAULT_URL` / `VAULT_EMAIL` (or the older `RBW_BASE_URL` / `RBW_EMAIL`), else `~/.config/rbw/config.json` |
| each git profile's host, owner and email | `GIT_PERSONAL_HOST` / `_OWNER` / `_EMAIL` (and `GIT_WORK_*`), else the files the old git role wrote |

Without a terminal, `chezmoi init --promptDefaults` takes the defaults.

### Git profiles and signing

A repo takes its `user.email` (and signing key) from its remote URL —
`git@github.com:…` for personal, and for work either the org on the same host
(`git@github.com:<org>/…`, the profile's owner) or an `~/.ssh/config` alias
such as `git@<work-alias>:…` (the profile's host). Commits and tags are signed
with the Bitwarden agent key whose comment is the repo's `user.email`, looked
up at commit time by `~/.config/git/signing-key`, so no key is stored in git's
config and the vault must be unlocked to commit.

ssh can only pick one of the agent's keys through a key file, so chezmoi
writes each profile's public half to `~/.ssh/git-profiles/<profile>.pub` and
points that profile's `Host` block at it. An owner-scoped profile shares its
host, so its `core.sshCommand` skips `~/.ssh/config` and offers only its key.
The owner match is case-sensitive, like git's globs. `git config user.email`
inside a repo shows which profile it got.

The keys are read from the agent at apply time. While Bitwarden is locked,
chezmoi keeps the ones an earlier apply wrote; on a fresh machine, unlock it
and `chezmoi apply` again to switch signing on. On Windows, git talks to
Windows' own OpenSSH (`C:/Windows/System32/OpenSSH`), whose default pipe
Bitwarden's agent takes over; Git for Windows' bundled ssh can't reach it.

### Secrets

`sync-secrets` fetches the API keys listed under `vault.secrets` in `home/.chezmoidata/vault.yaml`
from Vaultwarden into an owner-only directory, and opencode's config refers to
them by path. chezmoi never renders a key. The keys persist on disk — both
disks are encrypted (LUKS / BitLocker) — so they survive reboots until rotated
or expired; exclude the directory from any home backup.

- **Linux**: rbw, into `~/.local/share/dotfiles/secrets`.
- **Windows**: the Bitwarden CLI (`bw`), into
  `%LOCALAPPDATA%\dotfiles\secrets`, readable only by you.
  `bw` keeps no session between runs, so each `sync-secrets` asks for the
  master password; rbw caches its unlock, so Linux asks only after
  `vault.rbw.lockTimeout` (8 h) or an expired login.

`sync-secrets --check` (`-Check` on Windows) only runs the smoke tests.

## Windows

From Windows PowerShell (the built-in one is enough) as yourself, not as
Administrator:

```powershell
irm https://raw.githubusercontent.com/ahuca/dotfiles/main/bootstrap.ps1 | iex
```

It installs Git if needed and clones to `~\Projects\dotfiles`. Then it runs
`winget configure -f windows\configuration.winget`, which raises one UAC prompt
for the machine-wide settings. Last it runs `chezmoi init --apply`, which asks
the [per-machine questions](#per-machine-values), and `sync-secrets`. From a
checkout: `.\bootstrap.ps1`, or `.\bootstrap.ps1 -SkipConfigure` for just the
dotfiles and secrets. Needs winget 1.10.280 or later, for per-resource
elevation.

`windows/configuration.winget` installs:

- **Shell**: PowerShell 7, Windows Terminal, Oh My Posh.
- **Dotfiles and secrets**: chezmoi, Bitwarden, Bitwarden CLI.
- **Dev tools**: Git, GitHub CLI, delta, lazygit, ripgrep, fzf, fd, Neovim
  (and WinLibs GCC, which builds its tree-sitter parsers), glow, tealdeer,
  7-Zip, topgrade, Node.js LTS, VS Code, Claude Code, opencode, uv
  (opencode's Atlassian MCP runs under `uvx`).
- **Desktop**: Ditto (the CopyQ stand-in), ONLYOFFICE Desktop Editors, Everything.

It also disables Windows' OpenSSH agent service, so Bitwarden's agent gets
its pipe. To add
a package, copy a `WinGetPackage` entry and change its ids (`winget search
<name>`).

After the run:

- Bitwarden: **Settings → Enable SSH agent**, unlock the vault, then
  `chezmoi apply` so git finds the signing keys.
- Open a new Windows Terminal: PowerShell 7 is the default profile, with Oh My
  Posh's default theme in CaskaydiaCove Nerd Font. `oh-my-posh init pwsh
  --config <theme>` in `~\.config\powershell\profile.ps1` picks another.

Not tested on real Windows yet: the WinGet file, the scripts and the templates
were only parsed, and rendered on Linux with the OS switched.

## `tpm-unlock.yml` — LUKS auto-unlock via TPM2

Binds the LUKS volume behind `/` to the TPM with clevis, so the disk unlocks at
boot. **Your passphrase stays as the fallback in slot 0** — nothing here
touches it.

```bash
cd linux
ansible-playbook playbooks/tpm-unlock.yml -K                        # first-time bind
ansible-playbook playbooks/tpm-unlock.yml -K -e tpm_rebind=true     # re-seal against current PCRs
ansible-playbook playbooks/tpm-unlock.yml -K -e tpm_pcrs=0,7        # custom PCR set
ansible-playbook playbooks/tpm-unlock.yml -K -e tpm_device=/dev/nvme0n1p3
```

The playbook prompts for your current disk passphrase; clevis needs it to
authenticate the new keyslot.

There is no in-place "reseal" because `clevis luks regen` has to unseal the
existing key from the TPM first — and after a firmware or Secure Boot change
the PCRs have already moved, so that unseal fails. `tpm_rebind=true` drops the
stale slot and creates a fresh one against today's PCRs instead.

**Guard rail:** on a dracut system the playbook purges `clevis-initramfs` if it
finds it. That package pulls in `initramfs-tools`, which evicts dracut and
produces an initrd with no cryptsetup — an unbootable machine that drops to an
`(initramfs)` prompt.

After a BIOS/firmware or Secure Boot change, boot will ask for the passphrase
again; type it, then re-run with `-e tpm_rebind=true`. Consider a BIOS
supervisor password so nobody can boot a USB stick to release the key via PCR7.

## `vmware.yml` — VMware Workstation

The old script's subcommands are now tags:

```bash
cd linux
ansible-playbook playbooks/vmware.yml -K -e vmware_vm_dir=~/vmware/win10  # full setup
ansible-playbook playbooks/vmware.yml -K --tags modules                   # after a kernel bump
ansible-playbook playbooks/vmware.yml -K --tags sign                      # sign already-built modules
ansible-playbook playbooks/vmware.yml -K --tags mok                       # enroll the signing key
ansible-playbook playbooks/vmware.yml -K --tags tmp                       # move VMware's scratch off /tmp
ansible-playbook playbooks/vmware.yml -K --tags perms -e vmware_vm_dir=~/vmware/other
ansible-playbook playbooks/vmware.yml -K --tags status                    # diagnose only
ansible-playbook playbooks/vmware.yml --tags keyboard                     # forward host hotkeys to the guest
ansible-playbook playbooks/vmware.yml --tags scaling                      # draw VMware at 1x under Xwayland
ansible-playbook playbooks/vmware.yml --tags clipboard                    # copy/paste fixes on Wayland
```

Which tag fixes what:

| Symptom                                       | Tag       |
|-----------------------------------------------|-----------|
| Secure Boot rejects unsigned `vmmon`/`vmnet`  | `modules` |
| `.vmem` "No space left on device" on tmpfs    | `tmp`     |
| "Insufficient permission" (snapshot/lock)     | `perms`   |
| Host eats Super / Alt+Tab instead of the guest | `keyboard` |
| Guest mouse glitches with mixed-scale monitors | `scaling` |
| Host → guest copy/paste does nothing (guest → host works) | `clipboard` |
| Folders copied in the guest won't paste in Nautilus | `clipboard` |

MOK enrollment cannot be fully automated — it needs the blue **MOK Management**
screen at boot. The playbook queues the request and stops; reboot, choose
*Enroll MOK → Continue → Yes*, enter the password, reboot, then re-run with
`--tags modules`. That screen uses a US QWERTY layout and hides what you type.

The `clipboard` tag installs a user service, `vmware-clipboard-bridge`. GNOME's
Xwayland clipboard bridge never serves the `TIMESTAMP` target, and VMware only
sends the host clipboard when that timestamp changes, so nothing copied in a
Wayland app reaches the guest ([mutter#1265](https://gitlab.gnome.org/GNOME/mutter/-/work_items/1265)).
While VMware runs, the service re-owns each such clipboard as an X11 client that
does serve it. Ready-made Wayland⇄X11 clipboard syncers don't work here: they
need a data-control protocol that mutter doesn't implement.

The service also fixes folders copied out of a guest. VMware stages them under
`/tmp/VMwareDnD/<id>/`, but serves the same list for every target with the
staging dir left out of the paths: one folder as a bare `file:/<id>/<name>`
without the `copy` line Nautilus needs, several after an
`x-special/nautilus-clipboard` line. Nautilus refuses both ("Nautilus Clipboard
must begin with “cut” or “copy”"). The service takes that clipboard over with
the list fixed. Files alone come through right and are left alone.

Never run `vmware-modconfig --install-all` after signing — it rebuilds the
modules unsigned and silently undoes the signing.
