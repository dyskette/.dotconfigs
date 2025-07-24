function New-SshKey {
    param (
        [string]$KeyType = "ed25519"
    )

    # Prompt for email
    $email = Read-Host "Enter your email for the SSH key"

    if ([string]::IsNullOrWhiteSpace($email)) {
        Write-Host "[ERROR] No email provided. Aborting."
        return
    }

    # Prompt for key filename
    $keyName = Read-Host "Enter the name for your SSH key file (e.g. id_ed25519_github)"

    if ([string]::IsNullOrWhiteSpace($keyName)) {
        Write-Host "[ERROR] No key name provided. Aborting."
        return
    }

    # Build full key file path
    $sshFolder = Join-Path $env:USERPROFILE ".ssh"
    $keyPath = Join-Path $sshFolder $keyName
    $pubKeyPath = "$keyPath.pub"

    # Ensure .ssh folder exists
    if (-not (Test-Path $sshFolder)) {
        New-Item -ItemType Directory -Path $sshFolder | Out-Null
    }

    # Build and run ssh-keygen command
    $sshKeygenCmd = "ssh-keygen -t $KeyType -C `"$email`" -f `"$keyPath`""
    Write-Host "`n[INFO] Generating SSH key at: $keyPath"
    Invoke-Expression $sshKeygenCmd

    # Start and enable ssh-agent
    Write-Host "`n[INFO] Starting ssh-agent..."
    Get-Service -Name ssh-agent -ErrorAction SilentlyContinue | Set-Service -StartupType Automatic
    Start-Service ssh-agent

    # Add the key to the agent
    $sshAddCmd = "ssh-add `"$keyPath`""
    Write-Host "`n[INFO] Adding SSH key to ssh-agent..."
    Invoke-Expression $sshAddCmd

    # Copy public key to clipboard
    if (Test-Path $pubKeyPath) {
        Get-Content $pubKeyPath | Set-Clipboard
        Write-Host "`n[OK] Public key copied to clipboard!"
    } else {
        Write-Host "`n[ERROR] Public key not found to copy."
    }

    # Friendly summary
    Write-Host "`n[OK] SSH key created and added to agent."
    Write-Host "[INFO] Private key path: $keyPath"
    Write-Host "[INFO] Public key path : $pubKeyPath"
    Write-Host "[INFO] Public key has been copied - paste it into GitHub, GitLab, or your server!"
}

New-SshKey
