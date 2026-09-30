<#
.SYNOPSIS
    Toggle the psmux theme between dark and light (Windows counterpart of
    toggle-theme.sh).
#>

# show-environment ignores the variable name in psmux and prints every
# variable, so filter the line ourselves.
$current = psmux show-environment -g SYSTEM_COLOR_THEME 2>$null |
    Where-Object { $_ -like 'SYSTEM_COLOR_THEME=*' } |
    ForEach-Object { $_.Split('=', 2)[1] }

$next = if ($current -eq 'light') { 'dark' } else { 'light' }

& (Join-Path $PSScriptRoot 'set-theme.ps1') $next
psmux display-message "Theme: $next"
