#!/usr/bin/env bash
# Install Ansible, provision this machine from linux/, then apply the
# dotfiles in home/ with chezmoi.
#
#   ./bootstrap.sh                 # run site.yml
#   ./bootstrap.sh --tags packages # args go straight to ansible-playbook
#   ./bootstrap.sh -- playbooks/vmware.yml --tags status
#   ANSIBLE_SOURCE=apt ./bootstrap.sh   # distro ansible-core instead of pipx
#
# Fresh machine, nothing cloned yet:
#   wget -qO- https://raw.githubusercontent.com/ahuca/dotfiles/main/bootstrap.sh | bash

set -euo pipefail

log()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\n\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

command -v apt-get >/dev/null || die "This repo targets Debian/Ubuntu (apt) systems."

# --- piped from the web: clone, then re-run from the checkout ------------
# The repo is public, so this needs no credentials. stdin is the pipe (this
# script's own text), so the re-run gets the terminal back for its prompts.
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/ahuca/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Projects/dotfiles}"
if [[ ! -f "${BASH_SOURCE[0]:-}" ]]; then
  command -v git >/dev/null || { sudo apt-get update && sudo apt-get install -y git; }
  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    log "Updating $DOTFILES_DIR"
    git -C "$DOTFILES_DIR" pull --ff-only
  else
    log "Cloning $DOTFILES_REPO into $DOTFILES_DIR"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi
  # No controlling terminal (CI, cloud-init): re-run without prompts.
  if (exec </dev/tty) 2>/dev/null; then
    exec bash "$DOTFILES_DIR/bootstrap.sh" "$@" </dev/tty
  fi
  exec bash "$DOTFILES_DIR/bootstrap.sh" "$@" </dev/null
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$REPO_DIR/linux"
ANSIBLE_SOURCE="${ANSIBLE_SOURCE:-pipx}"

# -k: a cached sudo ticket would pass -n, but Ansible's become cannot use it.
SUDO_NOPASSWD=0
sudo -k -n true 2>/dev/null && SUDO_NOPASSWD=1

# Ask once: validating warms the ticket for this script's own sudo calls, and
# the same password goes to Ansible via a pipe (never argv, env or disk).
# Not ANSIBLE_BECOME_PASS: every unprivileged task, nvm's and Homebrew's
# downloaded installers included, would inherit it.
SUDO_PASS=""
if [[ "$SUDO_NOPASSWD" -eq 0 ]]; then
  [[ -t 0 ]] || die "sudo needs a password, but there is no terminal to ask on."
  sudo -k
  for _ in 1 2 3; do
    read -rsp "sudo password: " SUDO_PASS; echo
    printf '%s\n' "$SUDO_PASS" | sudo -S -p '' -v 2>/dev/null && break
    SUDO_PASS=""
    warn "Sorry, try again."
  done
  [[ -n "$SUDO_PASS" ]] || die "sudo authentication failed."
fi

PLAYBOOK="site.yml"
if [[ "${1:-}" == "--" ]]; then
  shift
  [[ $# -gt 0 ]] && { PLAYBOOK="$1"; shift; }
fi
EXTRA_ARGS=("$@")

# --- ansible -----------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"

case "$ANSIBLE_SOURCE" in
  pipx)
    if ! command -v pipx >/dev/null; then
      log "Installing pipx"
      sudo apt-get update
      sudo apt-get install -y pipx python3-venv
    fi
    if pipx list --short 2>/dev/null | grep -q '^ansible-core '; then
      log "Upgrading ansible-core to the latest release"
      pipx upgrade ansible-core || true
    else
      log "Installing the latest ansible-core with pipx"
      pipx install ansible-core
    fi
    pipx ensurepath >/dev/null 2>&1 || true
    if dpkg -s ansible-core >/dev/null 2>&1; then
      warn "The apt 'ansible-core' package is also installed ($(dpkg-query -W -f='${Version}' ansible-core)).
   ~/.local/bin takes precedence, so the pipx one is what runs. To drop the
   distro copy:  sudo apt-get purge ansible ansible-core"
    fi
    ;;
  apt)
    if ! command -v ansible-playbook >/dev/null; then
      log "Installing ansible-core from apt"
      sudo apt-get update
      sudo apt-get install -y ansible-core
    fi
    ;;
  *) die "ANSIBLE_SOURCE must be 'pipx' or 'apt' (got: $ANSIBLE_SOURCE)" ;;
esac

command -v ansible-playbook >/dev/null || die "ansible-playbook still not on PATH."
log "Using $(ansible-playbook --version | head -1) from $(command -v ansible-playbook)"

# For the system python, which Ansible uses on the target even from pipx.
log "Installing Ansible's runtime helpers"
sudo apt-get install -y python3-apt python3-psutil dbus

log "Installing Ansible collections"
ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml"

# --- run ---------------------------------------------------------------
log "Running $PLAYBOOK"
cd "$ANSIBLE_DIR"
# A named FIFO, not <(...): Ansible realpath()s the argument, which turns
# /dev/fd/N into an unopenable pipe:[...]. Nor "-", which would eat stdin that
# vars_prompt needs. The writer blocks until Ansible reads it once.
BECOME_ARGS=()
if [[ -n "$SUDO_PASS" ]]; then
  become_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/bootstrap.XXXXXX")"
  mkfifo -m 600 "$become_dir/pass"
  printf '%s\n' "$SUDO_PASS" >"$become_dir/pass" &
  become_writer=$!
  trap 'kill "$become_writer" 2>/dev/null || true; rm -rf "$become_dir"' EXIT
  unset SUDO_PASS
  BECOME_ARGS=(--become-password-file "$become_dir/pass")
fi
ansible-playbook "$PLAYBOOK" ${BECOME_ARGS+"${BECOME_ARGS[@]}"} ${EXTRA_ARGS+"${EXTRA_ARGS[@]}"}

# --- dotfiles ----------------------------------------------------------
# Everything under $HOME (git, ssh, zsh, the secrets plumbing) comes from
# home/ via chezmoi, which the playbook installs. The first init asks for the
# few personal values (git identity and profiles, Vaultwarden URL and login)
# and keeps them in ~/.config/chezmoi/chezmoi.toml, outside this repo.
# VAULT_URL / VAULT_EMAIL, GIT_<PROFILE>_HOST/_OWNER/_EMAIL pre-fill them.
# Only after a whole workstation run; a dry run shows the diff instead.
args=" ${EXTRA_ARGS[*]-} "
tags_re='(^| )(--tags|-t)[= ]'
check_re='(^| )(--check|-C)( |$)'
applied=0
if [[ "$PLAYBOOK" == site.yml || "$PLAYBOOK" == *workstation.yml ]] \
   && ! [[ "$args" =~ $tags_re ]]; then
  # Homebrew's prefix, as the homebrew role has it.
  brew_prefix="$(sed -n 's/^homebrew_prefix: *//p' "$ANSIBLE_DIR/group_vars/all.yml")"
  export PATH="${brew_prefix:-/home/linuxbrew/.linuxbrew}/bin:$PATH"
  if ! command -v chezmoi >/dev/null; then
    warn "chezmoi is not installed (homebrew role), so the dotfiles were not applied."
  elif [[ "$args" =~ $check_re ]]; then
    if [[ -f "$HOME/.config/chezmoi/chezmoi.toml" ]]; then
      log "Dotfiles that chezmoi would change"
      chezmoi diff --no-pager || true
    fi
  else
    log "Applying the dotfiles in home/ with chezmoi"
    init_args=(--apply --source "$REPO_DIR")
    [[ -t 0 ]] || init_args+=(--promptDefaults)
    # A cancelled prompt (seen after arrow keys, whose escape sequence starts
    # with Esc) stops init without saving anything, yet it still exits 0;
    # the missing config file gives it away.
    if chezmoi init "${init_args[@]}" && [[ -f "$HOME/.config/chezmoi/chezmoi.toml" ]]; then
      applied=1
    else
      warn "chezmoi stopped before saving its answers, so nothing was applied.
   Esc or an arrow key at a prompt seems to cancel it; answer with text and Enter.
   Re-run:  chezmoi init --apply --source \"$REPO_DIR\""
    fi
  fi
fi

# --- secrets -----------------------------------------------------------
# Log in and fill the key files, so a fresh machine is one command.
if [[ "$applied" -eq 1 && -t 0 && -x "$HOME/.local/bin/sync-secrets" ]] \
   && command -v rbw >/dev/null; then
  log "Logging in to Vaultwarden and refreshing secrets"
  rbw login && "$HOME/.local/bin/sync-secrets" \
    || warn "sync-secrets reported a problem (see above). Re-run:  sync-secrets"
fi
