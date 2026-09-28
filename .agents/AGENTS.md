# AGENTS.md

## No personal, private or sensitive data in the repo

Nothing that identifies the owner or a machine is committed: no names, emails,
usernames, hostnames, URLs of private services, SSH/GPG public keys, key
fingerprints, tokens, API keys or passwords — not even in comments or examples.

Resolve such values at runtime instead, following the existing pattern:

- environment variables (`lookup('env', ...)`, as `RBW_BASE_URL` / `RBW_EMAIL`)
- what the machine already knows (`~/.config/rbw/config.json`, `git config
  user.email`, `ssh-add -L` from the Bitwarden agent)
- secrets from Vaultwarden via `rbw`, fetched at runtime into tmpfs

When a value can't be found, the role skips with a pointer rather than failing.
Before committing, grep the diff for anything that looks personal.

## Conventional Commits

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/)
with the Ansible role (or area) as scope: `feat(git): ...`, `fix(vmware): ...`.
Pick the type by the change — `feat`, `fix`, `docs`, `refactor`, `chore`.
