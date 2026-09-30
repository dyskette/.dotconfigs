<#
.SYNOPSIS
    Helpers shared by the psmux popup scripts. Dot-source it; not meant to be
    run directly.

.NOTES
    Inside a popup psmux reaches the right server through
    PSMUX_TARGET_SESSION even though $env:TMUX is empty.
#>

<#
.SYNOPSIS
    Pick a directory under $HOME (up to 3 levels deep) with fzf.
.OUTPUTS
    The selected path, or nothing when the picker is cancelled.
#>
function Select-HomeDirectory {
    param([Parameter(Mandatory)][string]$Header)

    fd --type directory --max-depth 3 --exclude .git --exclude node_modules --exclude .venv --hidden . $HOME |
        Sort-Object |
        fzf --reverse `
            --header=$Header `
            --border=none `
            --preview-window=border-left `
            --preview="eza --tree --git-ignore --level 2 --colour=always --icons=always {}"
}

<#
.SYNOPSIS
    Build a session name from a directory's leaf name. psmux, like tmux,
    rejects '.' and ':' in session names; spaces are replaced for easier
    targeting.
#>
function ConvertTo-SessionName {
    param([Parameter(Mandatory)][string]$Path)

    (Split-Path -Leaf $Path.TrimEnd('\', '/')) -replace '[.: ]', '_'
}

<#
.SYNOPSIS
    Switch to the session for a directory, creating it first if needed.
.OUTPUTS
    The session name.
#>
function Switch-ToDirectorySession {
    param([Parameter(Mandatory)][string]$Path)

    $name = ConvertTo-SessionName $Path
    psmux has-session -t $name 2>$null
    if ($LASTEXITCODE -ne 0) {
        psmux new-session -d -s $name -c $Path
    }
    psmux switch-client -t $name
    $name
}
