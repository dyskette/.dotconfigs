#Requires -Version 7
<#
.SYNOPSIS
For a session started from a plain terminal (numeric default name): pick a
working directory, move to a session named after it, and drop the original.

.NOTES
Run once per server from the client-attached hook in psmux.conf, inside a
display-popup; errors go to the psmux status line.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Psmux.psm1')

try {
    $current = (Invoke-PsmuxCommand -Arguments @('display-message', '-p', '#S') | Select-Object -First 1)
    if ("$current" -notmatch '^\d+$') { return }

    $selected = Select-HomeDirectory -Header 'select-working-directory'
    if (-not $selected) { return }

    $name = Switch-ToDirectorySession -Path $selected
    if ($name -ne $current) {
        # '=': exact name, so session 0 never matches 01.
        Invoke-PsmuxCommand -Arguments @('kill-session', '-t', "=$current") | Out-Null
    }
} catch {
    Show-PsmuxMessage "first session: $($_.Exception.Message)"
    exit 1
}
