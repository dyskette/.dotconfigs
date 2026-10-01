# Window switcher for psmux (current session).
$selected = psmux list-windows -F '#{session_name}:#{window_index}: #{window_name} (#{window_panes} panes) #{?window_active,[active],}' |
    fzf --reverse `
        --header jump-to-window `
        --border=none `
        --preview-window=border-left `
        --delimiter=: `
        --preview 'psmux list-panes -t {1}:{2} -F "#{?pane_active,* ,  }#{pane_index}: #{pane_current_command} #{pane_current_path}"'

if ($selected) {
    $target = ($selected -split ':')[0..1] -join ':'
    $output = psmux select-window -t $target 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Keep the popup open rather than close silently on a refused switch.
        Write-Host "Could not select window '$target': $output" -ForegroundColor Red
        $null = Read-Host 'Press Enter to close'
    }
}
