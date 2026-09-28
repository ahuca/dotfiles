# dotfiles — local provisioning with Ansible

Ansible playbooks that provision this Ubuntu workstation against itself.
Nothing here talks to a remote host: the inventory is `localhost` with
`ansible_connection=local`.

```
bootstrap.sh          installs Ansible + collections, then runs site.yml
ansible/
  site.yml            default entry point -> playbooks/workstation.yml
  inventory.ini       localhost, local connection
  group_vars/all.yml  ALL the configuration (package lists, repos, hotkeys, ...)
  playbooks/
    workstation.yml   everyday setup: repos, packages, desktop, shell, node, brew
    tpm-unlock.yml    bind the LUKS root volume to the TPM2 (clevis)
    vmware.yml        VMware Workstation modules, MOK signing, temp dir, perms, hotkeys, scaling, clipboard
  roles/              one role per concern
```

## Quick start

Fresh machine, nothing cloned (the repo is public, so no credentials needed):

```bash
wget -qO- https://raw.githubusercontent.com/ahuca/dotfiles/main/bootstrap.sh | bash
```

It clones to `~/Projects/dotfiles`, provisions, then runs `rbw login` and
`sync-secrets`. You type your sudo password once (bootstrap checks it, then
reuses it for its own `sudo` calls and hands it to Ansible through a pipe as
the become password) and your Vaultwarden master password; on a machine's
first run it also asks for the Vaultwarden URL and
login email once. Those two are deliberately not in this repo; afterwards they
are read back from `~/.config/rbw/config.json` (or set `RBW_BASE_URL` /
`RBW_EMAIL`). Press Enter at the URL prompt to skip secrets entirely.

From an existing checkout:

```bash
./bootstrap.sh
```

### Ansible version

`bootstrap.sh` installs the **latest upstream `ansible-core`** with pipx into
`~/.local/bin`, because Ubuntu's archive trails upstream (resolute ships
ansible-core 2.20.1 against 2.21.4 upstream). Collections come from
`ansible/requirements.yml` rather than the distro bundle.

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
cd ansible
ansible-playbook site.yml -K                 # everything
ansible-playbook site.yml -K --check         # dry run
ansible-playbook site.yml -K --tags packages # just the package installs
ansible-playbook site.yml -K --tags copyq    # just the CopyQ hotkey
ansible-playbook site.yml -K --tags ghostty  # just the Ghostty config
ansible-playbook site.yml -K --tags docker   # just Docker Engine (and its repo)
ansible-playbook site.yml -K --tags git      # just git signing + profiles (unlock Bitwarden first)
ansible-playbook site.yml -K --skip-tags docker  # everything except Docker
```

`-K` prompts for the sudo password; drop it only if you have genuinely
passwordless (`NOPASSWD`) sudo. A warm sudo timestamp is not enough — Ansible's
become runs without a tty, and sudo-rs rejects a cached ticket there.

## What `workstation.yml` sets up

Preference throughout: **package managers only** — apt repo > snap > apt-installed `.deb`.

| Role       | What it does                                                                 |
|------------|------------------------------------------------------------------------------|
| `common`   | apt keyring dir, base tooling (curl, wget, git, gpg, …)                       |
| `apt_repos`| signing keys + deb822 `.sources` for Charm, VS Code, GitHub CLI, Claude Code, Edge, Microsoft prod (Intune) |
| `packages` | apt packages, snaps (Bitwarden, PowerShell), D2, UniFi Identity Desktop      |
| `docker`   | Docker's apt repo + Docker Engine, Buildx, Compose; you in the `docker` group |
| `desktop`  | CopyQ GNOME hotkey (Wayland-safe) + autostart; Super+Ctrl+T for "Always on top" (`wm_toggle_above_bindings`); opt-in `< > \|` on the key left of 1 (`xkb_lsgt_on_tlde`) |
| `ghostty`  | Ghostty config (`roles/ghostty/files/config.ghostty`, Windows Terminal-style keys) |
| `shell`    | zsh + oh-my-zsh (plugins: git, z), login shell, Bitwarden SSH-agent socket   |
| `git`      | SSH commit/tag signing with the Bitwarden agent key matching `user.email` (looked up per commit), allowed signers file; per-remote `user.email` profiles (`git_profiles`) with matching `~/.ssh/config` hosts |
| `nodejs`   | nvm + latest LTS node, set as the default                                     |
| `homebrew` | Linuxbrew + `opencode` (which pulls in ripgrep)                               |

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

Everything configurable lives in `ansible/group_vars/all.yml` — add a package
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

### After the run

- Log out and back in for zsh to take effect, and for the `docker` group.
- Bitwarden: **Settings → Enable SSH agent**, unlock the vault, add SSH-key
  items. The socket only exists once the agent is on; `ssh-add -l` then lists
  your keys.
- Git profiles: a repo takes its `user.email` (and signing key) from its
  remote URL — `git@github.com:…` for personal, and for work either the
  org on the same host (`git@github.com:<org>/…`, via `GIT_WORK_OWNER`) or
  an `~/.ssh/config` alias such as `git@<work-alias>:…`. Neither the emails,
  the org nor the alias are in this repo; give them once and later runs read
  them back from `~/.config/git/`:

  ```bash
  GIT_PERSONAL_EMAIL=… GIT_WORK_HOST=github.com GIT_WORK_OWNER=… GIT_WORK_EMAIL=… \
    ansible-playbook site.yml --tags git
  ```

  Each profile signs with, and ssh authenticates its host with, the Bitwarden
  key whose comment is its email, so unlock the vault first. All SSH keys
  live in Bitwarden: the role writes only their public halves, to
  `~/.ssh/bitwarden/<profile>.pub`, which the managed block at the top of
  `~/.ssh/config` points `IdentityFile` at (ssh has no other way to pick one
  agent key per host). An owner-scoped profile shares its host, so its
  `core.sshCommand` skips `~/.ssh/config` and offers only its key. The owner
  match is case-sensitive, like git's globs. `git config user.email` inside a
  repo shows which profile it got.

## `tpm-unlock.yml` — LUKS auto-unlock via TPM2

Binds the LUKS volume behind `/` to the TPM with clevis, so the disk unlocks at
boot. **Your passphrase stays as the fallback in slot 0** — nothing here
touches it.

```bash
cd ansible
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
cd ansible
ansible-playbook playbooks/vmware.yml -K -e vmware_vm_dir=~/vmware/win10  # full setup
ansible-playbook playbooks/vmware.yml -K --tags modules                   # after a kernel bump
ansible-playbook playbooks/vmware.yml -K --tags sign                      # sign already-built modules
ansible-playbook playbooks/vmware.yml -K --tags mok                       # enroll the signing key
ansible-playbook playbooks/vmware.yml -K --tags tmp                       # move VMware's scratch off /tmp
ansible-playbook playbooks/vmware.yml -K --tags perms -e vmware_vm_dir=~/vmware/other
ansible-playbook playbooks/vmware.yml -K --tags status                    # diagnose only
ansible-playbook playbooks/vmware.yml --tags keyboard                     # forward host hotkeys to the guest
ansible-playbook playbooks/vmware.yml --tags scaling                      # draw VMware at 1x under Xwayland
ansible-playbook playbooks/vmware.yml --tags clipboard                    # host -> guest copy/paste on Wayland
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

Never run `vmware-modconfig --install-all` after signing — it rebuilds the
modules unsigned and silently undoes the signing.
