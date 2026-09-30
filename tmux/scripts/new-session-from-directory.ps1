# Create (or switch to) a psmux session from a directory under $HOME.
. (Join-Path $PSScriptRoot 'session-helpers.ps1')

$selected = Select-HomeDirectory -Header 'create-new-session'

if ($selected) {
    Switch-ToDirectorySession $selected | Out-Null
}
