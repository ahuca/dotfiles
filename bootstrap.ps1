# Provision this Windows machine: packages and machine-wide settings from
# windows\configuration.winget, then the dotfiles in home\ with chezmoi.
#
#   .\bootstrap.ps1                       from a checkout
#   .\bootstrap.ps1 -SkipConfigure        only the dotfiles and secrets
#
# Fresh machine, nothing cloned yet (the built-in Windows PowerShell is fine):
#   irm https://raw.githubusercontent.com/ahuca/dotfiles/main/bootstrap.ps1 | iex
#
# Run it as yourself, not as Administrator: winget raises its own UAC prompt
# for machine-wide installers and the settings that need it.
# Written for Windows PowerShell 5.1 too, since PowerShell 7 isn't there yet.
# No param() block: `irm | iex` runs the text, not a script file.

$ErrorActionPreference = 'Stop'
$SkipConfigure = ($args -contains '-SkipConfigure') -or [bool]$env:DOTFILES_SKIP_CONFIGURE

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Green }

# winget adds to PATH in the registry; this session only sees it re-read.
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is missing: install "App Installer" from the Microsoft Store, then re-run.'
}
$wingetArgs = @('--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')

# --- piped from the web: clone, then carry on from the checkout ------------
# The repo is public, so this needs no credentials.
$repoUrl = if ($env:DOTFILES_REPO) { $env:DOTFILES_REPO } else { 'https://github.com/ahuca/dotfiles.git' }
$repoDir = if ($env:DOTFILES_DIR) { $env:DOTFILES_DIR } else { Join-Path $HOME 'Projects\dotfiles' }
$here = $PSScriptRoot
if (-not $here -or -not (Test-Path (Join-Path $here 'windows\configuration.winget'))) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Step 'Installing Git'
        winget install --exact --id Git.Git @wingetArgs
        Update-SessionPath
    }
    if (Test-Path (Join-Path $repoDir '.git')) {
        Write-Step "Updating $repoDir"
        git -C $repoDir pull --ff-only
    } else {
        Write-Step "Cloning $repoUrl into $repoDir"
        git clone $repoUrl $repoDir
    }
    if ($LASTEXITCODE) { throw 'git could not fetch the repo.' }
    $here = $repoDir
}

# --- packages and machine-wide settings ---------------------------------
if (-not $SkipConfigure) {
    Write-Step 'Applying windows\configuration.winget (UAC may ask once)'
    winget configure --file (Join-Path $here 'windows\configuration.winget') `
        --accept-configuration-agreements --disable-interactivity
    if ($LASTEXITCODE) {
        Write-Warning "winget configure reported a problem (exit $LASTEXITCODE); carrying on with what it installed. Re-run:  winget configure -f windows\configuration.winget"
    }
    Update-SessionPath
}

# --- dotfiles -------------------------------------------------------------
# The first init asks for the few personal values (git identity and
# profiles, Vaultwarden URL and login) and keeps them in
# ~\.config\chezmoi\chezmoi.toml, outside this repo. VAULT_URL / VAULT_EMAIL
# and GIT_<PROFILE>_HOST/_OWNER/_EMAIL pre-fill them.
if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
    throw 'chezmoi is not installed (windows\configuration.winget).'
}
Write-Step 'Applying the dotfiles in home\ with chezmoi'
chezmoi init --apply --source $here
# A cancelled prompt (Esc, or an arrow key) stops init without saving
# anything, yet it still exits 0; the missing config file gives it away.
if ($LASTEXITCODE -or -not (Test-Path (Join-Path $HOME '.config\chezmoi\chezmoi.toml'))) {
    throw "chezmoi stopped before saving its answers, so nothing was applied. Esc or an arrow key at a prompt seems to cancel it. Re-run:  chezmoi init --apply --source $here"
}

# --- secrets --------------------------------------------------------------
# Log in and fill the key files, so a fresh machine is one command.
$sync = Join-Path $HOME '.local\bin\sync-secrets.ps1'
if ((Test-Path $sync) -and [Environment]::UserInteractive) {
    Write-Step 'Logging in to Vaultwarden and refreshing secrets'
    pwsh -NoProfile -File $sync
    if ($LASTEXITCODE) { Write-Warning 'sync-secrets reported a problem (see above). Re-run:  sync-secrets' }
}

Write-Step 'Done'
Write-Host @'
  - Bitwarden: Settings -> tick "Enable SSH agent", unlock the vault, add SSH-key
    items. Then `chezmoi apply` once more, so git picks up the signing keys.
  - Open a new Windows Terminal: PowerShell 7 with Oh My Posh is the default.
'@
