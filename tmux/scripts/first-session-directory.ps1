# On a session started from a plain terminal (numeric default name), pick a
# working directory, move to a session named after it and drop the original.
. (Join-Path $PSScriptRoot 'session-helpers.ps1')

$current = psmux display-message -p '#S'

if ($current -match '^\d+$') {
    $selected = Select-HomeDirectory -Header 'select-working-directory'

    if ($selected) {
        $name = Switch-ToDirectorySession $selected
        if ($name -ne $current) {
            psmux kill-session -t $current
        }
    }
}
