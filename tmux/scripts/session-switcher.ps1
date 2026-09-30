<#
.SYNOPSIS
    Session switcher for psmux, detached sessions sorted by recency.

.PARAMETER Preview
    Internal: render the fzf preview tree (windows and panes) for a session.
#>
param(
    [string]$Preview
)

if ($Preview) {
    $e = [char]27
    $yellow = "$e[33m"; $blue = "$e[34m"; $green = "$e[32m"; $cyan = "$e[36m"
    $bold = "$e[1m"; $reset = "$e[0m"
    $iconSession = [char]0xf490; $iconWindow = [char]0xf2d0; $iconPane = [char]0xea85
    $iconActive = [char]0xeacf; $iconInactive = [char]0xead7

    "$yellow$iconSession $Preview$reset"

    $windows = @(psmux list-windows -t $Preview -F '#{window_index}:#{window_name}:#{window_active}')
    for ($w = 0; $w -lt $windows.Count; $w++) {
        $winIdx, $winName, $winActive = $windows[$w] -split ':', 3
        $lastWindow = $w -eq $windows.Count - 1
        $winPrefix = if ($lastWindow) { '└──' } else { '├──' }
        $panePrefix = if ($lastWindow) { '    ' } else { '│   ' }

        if ($winActive -eq '1') {
            "$winPrefix $bold$blue$iconActive $iconWindow ${winIdx}: $winName$reset"
        } else {
            "$winPrefix $blue$iconInactive $iconWindow ${winIdx}: $winName$reset"
        }

        # Path last and split with a limit: Windows paths contain ':'.
        $panes = @(psmux list-panes -t "${Preview}:$winIdx" -F '#{pane_index}:#{pane_active}:#{pane_current_command}:#{pane_current_path}')
        for ($p = 0; $p -lt $panes.Count; $p++) {
            $paneIdx, $paneActive, $paneCmd, $panePath = $panes[$p] -split ':', 4
            $paneConn = if ($p -eq $panes.Count - 1) { '└──' } else { '├──' }
            $dir = Split-Path -Leaf $panePath

            if ($paneActive -eq '1') {
                "$panePrefix$paneConn $bold$green$iconActive $iconPane ${paneIdx}: $paneCmd$reset $cyan($dir)$reset"
            } else {
                "$panePrefix$paneConn $green$iconInactive $iconPane ${paneIdx}: $paneCmd$reset $cyan($dir)$reset"
            }
        }
    }
    return
}

$previewCommand = "pwsh -NoProfile -NonInteractive -File `"$PSCommandPath`" -Preview {1}"

$selected = psmux list-sessions -F '#{?session_attached,,#{session_activity}:#{session_name}}' |
    Where-Object { $_ } |
    Sort-Object { [long]($_ -split ':', 2)[0] } -Descending |
    ForEach-Object {
        $session = ($_ -split ':', 2)[1]
        $count = @(psmux list-windows -t $session).Count
        "$session ($count windows)"
    } |
    fzf --reverse `
        --header jump-to-session `
        --border=none `
        --preview-window=border-left `
        --ansi `
        --preview $previewCommand

if ($selected) {
    psmux switch-client -t ($selected -split ' ', 2)[0]
}
