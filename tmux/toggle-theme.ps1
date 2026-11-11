#Requires -Version 7
<#
.SYNOPSIS
Toggles the psmux theme between dark and light (psmux.conf, prefix + T).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'scripts\Psmux.psm1')

try {
    # Explicit target, as in set-theme.ps1: psmux CLI calls without -t can
    # reach another session.
    $target = if ($env:PSMUX_TARGET_SESSION) { @('-t', $env:PSMUX_TARGET_SESSION) } else { @() }

    # psmux before 3.4.0 ignored the variable name and printed every variable;
    # the filter keeps this working on those versions.
    $current = Invoke-PsmuxCommand -Arguments (@('show-environment') + $target + @('-g', 'SYSTEM_COLOR_THEME')) -NoThrow |
        Where-Object { "$_" -like 'SYSTEM_COLOR_THEME=*' } |
        ForEach-Object { "$_".Split('=', 2)[1] } |
        Select-Object -First 1

    $next = if ($current -eq 'light') { 'dark' } else { 'light' }
    & (Join-Path $PSScriptRoot 'set-theme.ps1') -Theme $next
    if ($LASTEXITCODE -eq 0) { Show-PsmuxMessage "Theme: $next" }
} catch {
    Show-PsmuxMessage "toggle-theme: $($_.Exception.Message)"
    exit 1
}
