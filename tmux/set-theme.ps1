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
time instead of 'psmux source-file': a source-file sent from the command line
drops custom key bindings (checked on psmux 3.4.0 with a throwaway -L server:
224 bindings became 222, both custom ones gone). Re-check on a psmux upgrade;
once it keeps them, this loop can become a single source-file call.

The theme only applies to the session this runs for. In psmux, "global" (-g)
options are per session: each new session loads ~/.psmux.conf itself, whose
run-shell runs this script for it.

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
    # Without -t, 'set-option -g' lands on the newest session (psmux 3.4.0),
    # so one session's config load or theme toggle would restyle another.
    # -q (set -gq) marks options newer tmux lacks; psmux gets them as plain -g.
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
