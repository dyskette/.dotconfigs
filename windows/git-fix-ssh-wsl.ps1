# Get Windows username
$username = $env:USERNAME
$winSshPath = "/mnt/c/Users/$username/.ssh"

Write-Host "🔄 Syncing SSH keys into WSL..."

# Build WSL shell command
$wslCommand = "cd ~ && mkdir -p .ssh && cp -r $winSshPath/* ~/.ssh && chmod 600 ~/.ssh/*"

# Run the shell commands inside WSL
wsl --distribution Ubuntu-24.04 --exec bash -c $wslCommand

Write-Host "`n✅ SSH keys copied into WSL and permissions set."

# Detect distro name
$distro = wsl sh -c "grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '\""'"
$distro = $distro.ToLower().Trim()

Write-Host "`n🔍 Detected WSL distro: $distro"

# Build install command based on distro
switch ($distro) {
    "ubuntu" {
        $installCmd = "sudo apt update && sudo apt install -y openssh-client"
    }
    "debian" {
        $installCmd = "sudo apt update && sudo apt install -y openssh-client"
    }
    "fedora" {
        $installCmd = "sudo dnf install -y openssh-clients"
    }
    "rhel" {
        $installCmd = "sudo dnf install -y openssh-clients"
    }
    default {
        Write-Host "🚨 Unsupported or unknown distro: $distro. Please install openssh manually."
        return
    }
}

# Install OpenSSH client
Write-Host "`n📦 Installing OpenSSH client..."
wsl sh -c "$installCmd"

Write-Host "`n✅ OpenSSH client installed in WSL ($distro). You're all set!"
