#Requires -Version 7
<#
.SYNOPSIS
For a session started from a plain terminal (numeric default name): pick a
project, move to its session, and drop the original.

.NOTES
Run once per server from the client-attached hook in psmux.conf, inside a
display-popup. The work is first-session-directory.sh, shared with tmux; this
only starts it with Git Bash, because the hook's nested quoting leaves no room
for the bash command line itself.
#>
[CmdletBinding()]
param()

& (Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe') (Join-Path $PSScriptRoot 'first-session-directory.sh')
exit $LASTEXITCODE
