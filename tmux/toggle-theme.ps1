<#
.SYNOPSIS
    Toggle the psmux theme between dark and light (Windows counterpart of
    toggle-theme.sh).
#>

# Explicit target for the same reason as in set-theme.ps1: psmux CLI calls
# without -t can reach another session.
$target = if ($env:PSMUX_TARGET_SESSION) { @('-t', $env:PSMUX_TARGET_SESSION) } else { @() }

# show-environment ignores the variable name in psmux and prints every
# variable, so filter the line ourselves.
$current = psmux show-environment @target -g SYSTEM_COLOR_THEME 2>$null |
    Where-Object { $_ -like 'SYSTEM_COLOR_THEME=*' } |
    ForEach-Object { $_.Split('=', 2)[1] }

$next = if ($current -eq 'light') { 'dark' } else { 'light' }

& (Join-Path $PSScriptRoot 'set-theme.ps1') $next
psmux display-message @target "Theme: $next"
