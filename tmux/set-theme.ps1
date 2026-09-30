<#
.SYNOPSIS
    Set the psmux theme (Windows counterpart of set-theme.sh).

.DESCRIPTION
    Sources the dark or light theme file and records the choice in the psmux
    global environment so toggle-theme.ps1 can read it back.

    Unlike set-theme.sh there is no synthetic OSC 11 response: psmux has no
    mode 2031 support and #{client_tty} is not a writable device.

.PARAMETER Theme
    'dark' or 'light'. When omitted, falls back to $env:SYSTEM_COLOR_THEME
    (set by the PowerShell profile) and then to the Windows app theme.
#>
param(
    [ValidateSet('dark', 'light')]
    [string]$Theme
)

# A separate variable: assigning an arbitrary value to $Theme would trip ValidateSet.
$selected = if ($Theme) { $Theme } else { $env:SYSTEM_COLOR_THEME }
if ($selected -notin 'dark', 'light') {
    $personalize = Get-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -ErrorAction SilentlyContinue
    $selected = if ($personalize.AppsUseLightTheme) { 'light' } else { 'dark' }
}

$themeFile = if ($selected -eq 'light') { 'rose-pine-dawn.conf' } else { 'gruvbox.conf' }

# The theme's "set -g <option> <value>" lines are replayed one psmux call at
# a time instead of `psmux source-file`, working around two psmux 3.3.8 bugs:
# a source-file sent from the command line resets every key binding to the
# defaults, and commands chained with ';' on the command line get dropped.
foreach ($line in Get-Content (Join-Path $PSScriptRoot $themeFile)) {
    if ($line -match '^\s*set(?:-option)?\s+-g\s+(\S+)\s+(?:"(.*)"|(\S+))\s*$') {
        $value = if ($null -ne $Matches[2]) { $Matches[2] } else { $Matches[3] }
        psmux set-option -g $Matches[1] $value 2>$null
    }
}

psmux set-environment -g SYSTEM_COLOR_THEME $selected
