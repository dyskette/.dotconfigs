@{
    # Scripts not yet rewritten to the Phase 1 conventions (see todo.md).
    # Lint findings in these files are reported but do not fail the checks, and
    # the convention tests in Repository.Tests.ps1 skip them.
    #
    # Remove a file from this list in the same commit that rewrites it; from then
    # on it is held to the full rule set. The list must only ever shrink.
    Legacy = @(
        'powershell/Microsoft.PowerShell_profile.ps1'
        'tmux/scripts/first-session-directory.ps1'
        'tmux/scripts/new-session-from-directory.ps1'
        'tmux/scripts/session-helpers.ps1'
        'tmux/set-theme.ps1'
        'tmux/toggle-theme.ps1'
        'windows/Configure-Dotfiles.ps1'
        'windows/Install-Extensions.ps1'
        'windows/Install-GitHubReleases.ps1'
        'windows/Install-WSL.ps1'
    )
}
