#Requires -Version 7
<#
.SYNOPSIS
Helpers for the psmux theme scripts (set-theme.ps1, toggle-theme.ps1).

.NOTES
psmux runs run-shell and display-popup commands with pwsh, with the user's
profile loaded. The profile defines a 'psmux' function (Invoke-Psmux), so these
helpers call psmux.exe by path to get plain psmux behaviour.

Inside a popup psmux reaches the right server through PSMUX_TARGET_SESSION even
though $env:TMUX is empty.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
Runs psmux.exe with the given arguments and returns its output.

.PARAMETER NoThrow
Return $null instead of throwing when psmux exits non-zero (has-session uses
the exit code as its answer).
#>
function Invoke-PsmuxCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$NoThrow
    )

    $exe = Get-Command psmux -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { throw 'psmux.exe is not on PATH.' }

    $output = & $exe.Source @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($NoThrow) { return $null }
        throw "psmux $($Arguments -join ' ') exited with ${LASTEXITCODE}: $(($output | Select-Object -Last 2) -join ' ')"
    }
    return $output
}

<#
.SYNOPSIS
Shows a message in the psmux status line. A popup closes as soon as its script
ends, so errors from popup scripts are reported here instead.
#>
function Show-PsmuxMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)

    $target = if ($env:PSMUX_TARGET_SESSION) { @('-t', $env:PSMUX_TARGET_SESSION) } else { @() }
    Invoke-PsmuxCommand -Arguments (@('display-message') + $target + $Message) -NoThrow | Out-Null
}

<#
.SYNOPSIS
Parses one 'set -g <option> <value>' theme line into Option and Value.

.DESCRIPTION
'set', 'set-option', '-g' and '-gq' are accepted; the value may be quoted.
Anything else (comments, other commands) returns nothing.
#>
function ConvertFrom-ThemeLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)

    if ($Line -match '^\s*set(?:-option)?\s+-gq?\s+(\S+)\s+(?:"(.*)"|(\S+))\s*$') {
        $value = if ($null -ne $Matches[2]) { $Matches[2] } else { $Matches[3] }
        [pscustomobject]@{ Option = $Matches[1]; Value = $value }
    }
}

Export-ModuleMember -Function Invoke-PsmuxCommand, Show-PsmuxMessage, ConvertFrom-ThemeLine
