# AGENTS.md

## No personal, private or sensitive data in the repo

Nothing that identifies the owner or a machine is committed: no names, emails,
usernames, hostnames, URLs of private services, SSH/GPG public keys, key
fingerprints, tokens, API keys or passwords — not even in comments or examples.

Resolve such values at runtime instead, following the existing pattern:

- environment variables (`lookup('env', ...)` in Ansible, `env` in chezmoi, as
  `VAULT_URL` / `VAULT_EMAIL`)
- what the machine already knows (`~/.config/rbw/config.json`, `git config
  user.email`, `ssh-add -L` from the Bitwarden agent)
- secrets from Vaultwarden via `rbw`, fetched at runtime into tmpfs

When a value can't be found, the role skips with a pointer rather than failing.
Before committing, grep the diff for anything that looks personal.

## Where a change goes

- Machine-wide on Ubuntu (packages, repos, GNOME, udev, systemd, root
  files): an Ansible role in `linux/`.
- Machine-wide on Windows (packages, services, elevated settings):
  `windows/configuration.winget`.
- Dotfiles under `$HOME`, on either OS: chezmoi's source state in `home/`,
  branching on `.chezmoi.os` where the platforms differ. Per-machine values
  are prompted once in `home/.chezmoi.toml.tmpl`, never committed. (A role
  may still drop a `$HOME` file that only serves its own feature, like the
  desktop role's autostart entry or the VMware clipboard user unit.)

Check a `home/` change with `chezmoi diff` before `chezmoi apply`.

## Conventional Commits

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/)
with the Ansible role (or area) as scope: `feat(git): ...`, `fix(vmware): ...`,
`feat(windows): ...`, `feat(chezmoi): ...`.
Pick the type by the change — `feat`, `fix`, `docs`, `refactor`, `chore`.
