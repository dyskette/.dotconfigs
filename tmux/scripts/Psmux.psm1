#Requires -Version 7
<#
.SYNOPSIS
Helpers for the psmux scripts (session pickers and themes).

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
True when a session with exactly this name exists ('=' disables prefix matching).
#>
function Test-PsmuxSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name)

    $null -ne (Invoke-PsmuxCommand -Arguments @('has-session', '-t', "=$Name") -NoThrow)
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
Picks a directory under $HOME with fd and fzf.

.OUTPUTS
The selected path, or nothing when the picker is cancelled.
#>
function Select-HomeDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Header,
        [int]$Depth = 3,
        [string[]]$Exclude = @('.git', 'node_modules', '.venv')
    )

    foreach ($tool in 'fd', 'fzf') {
        if (-not (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)) {
            throw "$tool is not on PATH; the directory picker needs fd and fzf."
        }
    }

    $fdArguments = @('--type', 'directory', '--max-depth', $Depth, '--hidden') +
        @($Exclude | ForEach-Object { '--exclude', $_ }) + @('.', $HOME)
    # fzf exits 130 when cancelled; that is not an error, just no selection.
    fd @fdArguments | Sort-Object |
        fzf --reverse "--header=$Header" --border=none --preview-window=border-left `
            '--preview=eza --tree --git-ignore --level 2 --colour=always --icons=always {}'
}

<#
.SYNOPSIS
Session name for a directory: its leaf name. psmux, like tmux, rejects '.' and
':' in session names; spaces are replaced for easier targeting.
#>
function ConvertTo-SessionName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    (Split-Path -Leaf $Path.TrimEnd('\', '/')) -replace '[.: ]', '_'
}

<#
.SYNOPSIS
Switches to the session for a directory, creating it first if needed.

.OUTPUTS
The session name.
#>
function Switch-ToDirectorySession {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    $name = ConvertTo-SessionName $Path
    if (-not (Test-PsmuxSession -Name $name)) {
        Invoke-PsmuxCommand -Arguments @('new-session', '-d', '-s', $name, '-c', $Path) | Out-Null
    }
    Invoke-PsmuxCommand -Arguments @('switch-client', '-t', "=$name") | Out-Null
    return $name
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

Export-ModuleMember -Function Invoke-PsmuxCommand, Test-PsmuxSession, Show-PsmuxMessage, Select-HomeDirectory,
    ConvertTo-SessionName, Switch-ToDirectorySession, ConvertFrom-ThemeLine
