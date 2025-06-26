# Get the full path to the ssh command being used
$sshPath = (Get-Command ssh).Source

Write-Host "🔍 Detected SSH path: $sshPath"

# Check if it's not from Git's usr/bin folder
if ($sshPath -notmatch 'git[\\\/]usr[\\\/]bin[\\\/]ssh\.exe') {
    # Convert backslashes to forward slashes for Git compatibility
    $gitFriendlyPath = $sshPath -replace '\\', '/'

    # Apply the SSH command override globally in Git
    git config --global core.sshCommand "$gitFriendlyPath"
    Write-Host "✅ Configured Git to use SSH at: $gitFriendlyPath"
} else {
    Write-Host "✅ SSH already points to Git's version, no changes made."
}
