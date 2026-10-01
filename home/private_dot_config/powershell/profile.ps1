# Managed by chezmoi (home/private_dot_config/powershell/profile.ps1).
# PowerShell 7 reads this itself on Linux. On Windows its own profile lives
# under Documents, which OneDrive may have moved, so chezmoi makes that one
# dot-source this file instead.

# ~/.local/bin on PATH, as in zsh (sync-secrets).
$localBin = Join-Path $HOME '.local/bin'
if ((Test-Path $localBin) -and ($env:PATH -split [IO.Path]::PathSeparator) -notcontains $localBin) {
    $env:PATH = $localBin + [IO.Path]::PathSeparator + $env:PATH
}

if ($Host.Name -eq 'ConsoleHost') {
    # Grey suggestions from history (→ accepts), like zsh-autosuggestions, and
    # a menu on Tab instead of cycling through completions one at a time.
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

    if (Get-Command oh-my-posh -ErrorAction Ignore) {
        # oh-my-posh dropped its built-in default config ("CONFIG NOT FOUND"
        # in the prompt without one). Use the stock theme from its themes
        # directory where it exists (winget installs it there), bare init else.
        $theme = if ($env:POSH_THEMES_PATH) { Join-Path $env:POSH_THEMES_PATH 'jandedobbeleer.omp.json' }
        if ($theme -and (Test-Path $theme)) {
            oh-my-posh init pwsh --config $theme | Invoke-Expression
        } else {
            oh-my-posh init pwsh | Invoke-Expression
        }
    }
}
