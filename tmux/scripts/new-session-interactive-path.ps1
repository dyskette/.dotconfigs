<#
.SYNOPSIS
    Interactive path builder with directory completion for a new psmux
    session.

.DESCRIPTION
    fzf reloads on every keystroke by re-invoking this script with -List, so
    the candidates are always the subdirectories of what has been typed.
    Both '\' and '/' are accepted as separators and a leading '~' expands to
    $HOME. Ctrl+Y copies the highlighted item into the query; Enter creates
    (or switches to) the session for the highlighted item.

.PARAMETER List
    Internal: print the directory candidates for a query.

.PARAMETER Preview
    Internal: render the fzf preview for a query (or the highlighted item
    when the query is empty).

.PARAMETER Item
    Internal: the highlighted item, used with -Preview.
#>
param(
    [switch]$List,
    [switch]$Preview,
    [Parameter(Position = 0)][string]$Query = '',
    [Parameter(Position = 1)][string]$Item = ''
)

$root = "$env:SystemDrive\"

function Expand-Query([string]$Path) {
    if ($Path -match '^~([\\/]|$)') { $Path = $HOME + $Path.Substring(1) }
    $Path
}

function Get-Subdirectory([string]$Path) {
    fd --type directory --max-depth 1 --exclude .git --hidden . $Path 2>$null | Sort-Object
}

if ($List) {
    $expanded = Expand-Query $Query
    if (-not $expanded) {
        Get-Subdirectory $root
    } elseif ($expanded -match '[\\/]$') {
        Get-Subdirectory $expanded
    } else {
        # Complete the last segment inside its parent directory.
        $cut = $expanded.LastIndexOfAny([char[]]'\/')
        $parent = if ($cut -ge 0) { $expanded.Substring(0, $cut + 1) } else { $root }
        $name = $expanded.Substring($cut + 1)
        if (Test-Path -LiteralPath $parent -PathType Container) {
            Get-Subdirectory $parent | Where-Object {
                (Split-Path -Leaf $_.TrimEnd('\', '/')) -like "*$name*"
            }
        }
    }
    return
}

if ($Preview) {
    $path = Expand-Query $(if ($Query) { $Query } elseif ($Item) { $Item } else { $root })
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        # Show the parent while a segment is still being typed.
        $path = Split-Path -Parent $path
        if (-not $path) { $path = $root }
        $level = 1
    } else {
        $level = 2
    }
    eza --tree --git-ignore --level $level --colour=always --icons=always $path 2>$null
    return
}

. (Join-Path $PSScriptRoot 'session-helpers.ps1')

$self = "pwsh -NoProfile -NonInteractive -File `"$PSCommandPath`""

$selected = Get-Subdirectory $root |
    fzf --query=$root `
        --prompt='Directory: ' `
        --header='Type path, Ctrl+Y to select item, Enter to create session' `
        --reverse `
        --border=none `
        --bind="change:reload:$self -List {q}" `
        --bind='ctrl-y:replace-query' `
        --preview="$self -Preview {q} {}" `
        --preview-window=right:60%:border-left

if ($selected) {
    $selected = Expand-Query $selected
    if (Test-Path -LiteralPath $selected -PathType Container) {
        Switch-ToDirectorySession $selected | Out-Null
    } else {
        psmux display-message "Directory does not exist: $selected"
    }
}
