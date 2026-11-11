#Requires -Version 7
<#
.SYNOPSIS
Sets the psmux theme.

.DESCRIPTION
Applies the dark or light theme file and records the choice in the psmux
global environment so toggle-theme.ps1 can read it back.

psmux has no theme detection of its own (tmux 3.6+ does, see tmux.conf), so
the theme comes from here instead.

The theme's "set -g <option> <value>" lines are replayed one psmux call at a
time instead of 'psmux source-file', working around two bugs seen in psmux
3.3.8: a source-file sent from the command line resets every key binding to
the defaults, and commands chained with ';' on the command line get dropped.
psmux is at 3.4.0 now; once 'psmux source-file <theme>' keeps the bindings,
this loop can go.

.PARAMETER Theme
'dark' or 'light'. When omitted, falls back to $env:SYSTEM_COLOR_THEME (set by
the PowerShell profile) and then to the Windows app theme.

.PARAMETER DarkTheme
Theme file (in this folder, without .conf) used for 'dark'.

.PARAMETER LightTheme
Theme file (in this folder, without .conf) used for 'light'.
#>
[CmdletBinding()]
param(
    [ValidateSet('dark', 'light')]
    [string]$Theme,
    [string]$DarkTheme = 'everforest-dark-medium',
    [string]$LightTheme = 'everforest-light-medium'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'scripts\Psmux.psm1')

try {
    # A separate variable: assigning an arbitrary value to $Theme would trip ValidateSet.
    $selected = if ($Theme) { $Theme } else { $env:SYSTEM_COLOR_THEME }
    if ($selected -notin 'dark', 'light') {
        $light = [Microsoft.Win32.Registry]::GetValue(
            'HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme', 0)
        $selected = if ($light) { 'light' } else { 'dark' }
    }

    $themeName = if ($selected -eq 'light') { $LightTheme } else { $DarkTheme }
    $themeFile = Join-Path $PSScriptRoot "$themeName.conf"
    if (-not (Test-Path -LiteralPath $themeFile)) {
        $available = (Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.conf' |
                Where-Object BaseName -notin 'common', 'psmux', 'pwsh', 'tmux' | ForEach-Object BaseName) -join ', '
        throw "theme '$themeName' not found; available: $available"
    }

    # Target the session this runs for (psmux exports it to run-shell commands).
    # 'set-option -g' without -t does not follow PSMUX_TARGET_SESSION and lands
    # on whichever session psmux picks, so one session's theme toggle would
    # restyle another. -q (set -gq) marks options newer tmux lacks; psmux gets
    # them as plain -g.
    $target = if ($env:PSMUX_TARGET_SESSION) { @('-t', $env:PSMUX_TARGET_SESSION) } else { @() }
    $failed = 0
    foreach ($setting in Get-Content -LiteralPath $themeFile | ForEach-Object { ConvertFrom-ThemeLine $_ }) {
        $result = Invoke-PsmuxCommand -Arguments (@('set-option') + $target + @('-g', $setting.Option, $setting.Value)) -NoThrow
        if ($null -eq $result) { $failed++ }
    }
    Invoke-PsmuxCommand -Arguments (@('set-environment') + $target + @('-g', 'SYSTEM_COLOR_THEME', $selected)) | Out-Null

    if ($failed -gt 0) { Show-PsmuxMessage "Theme ${themeName}: $failed option(s) were rejected" }
} catch {
    Show-PsmuxMessage "set-theme: $($_.Exception.Message)"
    exit 1
}
