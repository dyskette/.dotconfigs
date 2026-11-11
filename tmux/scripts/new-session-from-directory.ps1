#Requires -Version 7
<#
.SYNOPSIS
Creates or switches to a psmux session for a directory picked under $HOME.

.NOTES
Run in a display-popup (psmux.conf, prefix + S). The popup closes when this
script ends, so errors go to the psmux status line.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Psmux.psm1')

try {
    $selected = Select-HomeDirectory -Header 'create-new-session'
    if ($selected) {
        Switch-ToDirectorySession -Path $selected | Out-Null
    }
} catch {
    Show-PsmuxMessage "new session: $($_.Exception.Message)"
    exit 1
}
