#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Automated Windows development environment setup using WSL and Ansible

.DESCRIPTION
    This script installs WSL with Ubuntu 24.04, sets up Ansible within the Linux environment,
    and executes the ansible-playbook to install and configure Windows applications.
    
    Uses the modern WSL installation approach (wsl --install) which automatically:
    - Enables WSL and Virtual Machine Platform features
    - Downloads and installs the latest Linux kernel
    - Sets WSL 2 as the default
    - Downloads and installs Ubuntu 24.04 LTS

.NOTES
    Requirements:
    - Windows 10 version 2004+ (Build 19041+) or Windows 11
    - Administrator privileges
    - Internet connection
#>

param(
    [Parameter(HelpMessage="Install only VS Code application")]
    [switch]$VSCode,
    
    [Parameter(HelpMessage="Install only VS Code extensions")]
    [switch]$VSCodeExtensions,
    
    [Parameter(HelpMessage="Install only JetBrains Mono Nerd Font")]
    [switch]$JetBrainsFont,
    
    [Parameter(HelpMessage="Install only Chocolatey package manager")]
    [switch]$Chocolatey,
    
    [Parameter(HelpMessage="Install only MinGW compiler")]
    [switch]$MinGW,
    
    [Parameter(HelpMessage="Install only Deno runtime")]
    [switch]$Deno,
    
    [Parameter(HelpMessage="Install command-line tools (make, wget, jq, fzf, etc.)")]
    [switch]$CliTools,
    
    [Parameter(HelpMessage="Install only PowerShell Core")]
    [switch]$PowerShell,
    
    [Parameter(HelpMessage="Install only fnm (Fast Node Manager)")]
    [switch]$Fnm,
    
    [Parameter(HelpMessage="Install only Python 3.12")]
    [switch]$Python,
    
    [Parameter(HelpMessage="Install only Neovim")]
    [switch]$Neovim,
    
    [Parameter(HelpMessage="Install only Windows Terminal")]
    [switch]$WindowsTerminal,
    
    [Parameter(HelpMessage="Install productivity apps (Obsidian, Firefox, KeePassXC, Dropbox)")]
    [switch]$ProductivityApps,
    
    [Parameter(HelpMessage="Install only Yazi file manager")]
    [switch]$Yazi,
    
    [Parameter(HelpMessage="Configure Windows settings (Explorer, Virtual Desktops, etc.)")]
    [switch]$WindowsConfig,
    
    [Parameter(HelpMessage="Configure all applications (bat, PowerShell, Starship, Neovim, VS Code, Windows Terminal)")]
    [switch]$Configuration,
    
    [Parameter(HelpMessage="Configure bat")]
    [switch]$BatConfig,
    
    [Parameter(HelpMessage="Configure PowerShell")]
    [switch]$PowerShellConfig,
    
    [Parameter(HelpMessage="Configure Starship")]
    [switch]$StarshipConfig,
    
    [Parameter(HelpMessage="Configure Neovim")]
    [switch]$NeovimConfig,
    
    [Parameter(HelpMessage="Configure VS Code")]
    [switch]$VSCodeConfig,
    
    [Parameter(HelpMessage="Configure Windows Terminal")]
    [switch]$WindowsTerminalConfig,
    
    [Parameter(HelpMessage="Run all tasks (default behavior)")]
    [switch]$All,
    
    [Parameter(ValueFromRemainingArguments=$true, HelpMessage="Additional arguments to pass to ansible-playbook")]
    [string[]]$AdditionalArgs
)

function Get-MajorMinorVersion {
    param([string]$version)

    # Strip non-digit/dot characters, e.g., 'v1.11.400' -> '1.11.400'
    $clean = $version -replace '[^\d\.]', ''

    # Split version into parts
    $parts = $clean -split '\.'

    # Return array of integers: major, minor
    return @([int]$parts[0], [int]$parts[1])
}

function Install-WSLAndUbuntu {
    Write-Host "Installing WSL with Ubuntu 24.04 LTS..." -ForegroundColor Yellow
    
    # Use the modern WSL install command to install Ubuntu 24.04
    # This automatically enables WSL features, installs the kernel, sets WSL 2 as default, and installs Ubuntu 24.04
    wsl --install -d Ubuntu-24.04
    
    Write-Host "WSL and Ubuntu 24.04 LTS installation initiated." -ForegroundColor Green
    Write-Host "A restart will be required to complete the installation." -ForegroundColor Yellow
    Write-Host "After restart, Ubuntu will launch automatically for initial user setup." -ForegroundColor Yellow
}

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

# Check Windows version compatibility
$windowsVersion = [System.Environment]::OSVersion.Version
$requiredBuild = 19041

if ($windowsVersion.Build -lt $requiredBuild) {
    Write-Error "This script requires Windows 10 version 2004 (Build 19041) or higher, or Windows 11."
    Write-Host "Current Windows version: $($windowsVersion.Major).$($windowsVersion.Minor) (Build $($windowsVersion.Build))" -ForegroundColor Yellow
    Write-Host "Please update Windows before running this script." -ForegroundColor Yellow
    exit 1
}

Write-Host "Windows version check passed: Build $($windowsVersion.Build)" -ForegroundColor Green

# Enable WSL feature if not already enabled
Write-Host "Ensuring WSL feature is enabled..." -ForegroundColor Yellow
try {
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslFeature.State -ne "Enabled") {
        Write-Host "Enabling WSL feature..." -ForegroundColor Yellow
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
        Write-Host "WSL feature enabled." -ForegroundColor Green
    } else {
        Write-Host "WSL feature is already enabled." -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not check or enable WSL feature: $_"
}

# Install winget
$shouldInstallWinget = $false
$wingetUrl = ""

# Download latest release information
$tempFile = "$env:TEMP\winget_latest.json"
Invoke-WebRequest -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -OutFile $tempFile -UseBasicParsing

# Parse release information
$latestJson = (Get-Content $tempFile | ConvertFrom-Json)

$latestVersion = $latestJson.tag_name # e.g., v1.11.400
Write-Host "Latest Winget version: $latestVersion"

$latestVersion = Get-MajorMinorVersion $latestVersion

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "Winget not found. Will install."
    $shouldInstallWinget = $true
} else {
    $installedVersion = (winget --version)  # e.g., v1.6.10121
    Write-Host "Currently installed Winget version: $installedVersion"

    $installedVersion = Get-MajorMinorVersion $installedVersion

    if ($latestVersion[0] -gt $installedVersion[0] -or ($latestVersion[0] -eq $installedVersion[0] -and $latestVersion[1] -gt $installedVersion[1])) {
        Write-Host "New version available. Will reinstall."
        $shouldInstallWinget = $true
    } else {
        Write-Host "Winget is up to date."
    }
}

if ($shouldInstallWinget) {
    $wingetUrl = $latestJson.assets | Where-Object { $_.browser_download_url -like '*.msixbundle' } | Select-Object -ExpandProperty browser_download_url

    if (-not $wingetUrl) {
        Write-Host "Failed to find .msixbundle in release assets."
        Remove-Item -Force $tempFile
        exit 1
    }

    $msixPath = "$env:TEMP\Setup.msix"
    Write-Host "Downloading Winget from: $wingetUrl"
    Invoke-WebRequest -Uri $wingetUrl -OutFile $msixPath -UseBasicParsing

    # Install Winget
    try
    {
        Add-AppxPackage -Path $msixPath
        Write-Host "Winget installed successfully."
    } catch
    {
        Write-Host "Failed to install Winget."
        Remove-Item -Force $msixPath
        Remove-Item -Force $tempFile
        exit 1
    }

    # Update PATH environment variable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Clean up
    Remove-Item -Force $msixPath
}

Remove-Item -Force $tempFile

# Install Git if not present
if (-not(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing..." -ForegroundColor Yellow
    winget install --exact --id Git.Git --silent

    # Update PATH environment variable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
} else {
    Write-Host "Git is already installed." -ForegroundColor Green
}

# Check if WSL and Ubuntu 24.04 are available
$wslInstalled = $false
$ubuntuInstalled = $false

# Check if WSL is installed and working
try {
    $wslStatus = wsl --list --verbose 2>$null
    if ($LASTEXITCODE -eq 0) {
        $wslInstalled = $true
        Write-Host "WSL is available." -ForegroundColor Green
        
        # Check if Ubuntu 24.04 is installed
        $distributions = wsl --list --quiet
        if ($distributions -contains "Ubuntu-24.04") {
            $ubuntuInstalled = $true
            Write-Host "Ubuntu 24.04 is already installed." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "WSL is not available or not working properly." -ForegroundColor Yellow
}

# Install WSL and Ubuntu 24.04 if needed
if (-not $wslInstalled -or -not $ubuntuInstalled) {
    if (-not $ubuntuInstalled) {
        Write-Host "Ubuntu 24.04 not found. Installing WSL with Ubuntu 24.04..." -ForegroundColor Yellow
        Install-WSLAndUbuntu
        
        Write-Host ""
        Write-Host "=== INSTALLATION INITIATED ===" -ForegroundColor Cyan
        Write-Host "WSL and Ubuntu 24.04 installation has been started." -ForegroundColor White
        Write-Host ""
        Write-Host "NEXT STEPS:" -ForegroundColor Yellow
        Write-Host "1. Your computer will restart automatically" -ForegroundColor White
        Write-Host "2. After restart, Ubuntu will launch for initial setup" -ForegroundColor White
        Write-Host "3. Create your Linux username and password when prompted" -ForegroundColor White
        Write-Host "4. Run this script again: .\install.ps1" -ForegroundColor White
        Write-Host ""
        Write-Host "Press any key to restart now, or Ctrl+C to restart manually later..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        # Restart the computer
        # Restart-Computer -Force
        exit 0
    }
}

# Set Ubuntu 24.04 as default WSL distribution if it's installed
if ($ubuntuInstalled) {
    Write-Host "Setting Ubuntu 24.04 as default WSL distribution..." -ForegroundColor Yellow
    wsl --set-default Ubuntu-24.04
}

# Ensure Ubuntu is properly set up before proceeding
Write-Host "Checking Ubuntu 24.04 setup..." -ForegroundColor Blue

# Test if Ubuntu is properly initialized
try {
    $testResult = wsl --distribution Ubuntu-24.04 --exec echo "test" 2>$null
    if ($LASTEXITCODE -ne 0 -or $testResult -ne "test") {
        Write-Host ""
        Write-Host "=== UBUNTU SETUP REQUIRED ===" -ForegroundColor Yellow
        Write-Host "Ubuntu 24.04 is installed but needs initial setup." -ForegroundColor White
        Write-Host ""
        Write-Host "Please:" -ForegroundColor Yellow
        Write-Host "1. Open Ubuntu 24.04 from the Start menu" -ForegroundColor White
        Write-Host "2. Complete the initial user setup (username and password)" -ForegroundColor White
        Write-Host "3. Run this script again: .\install.ps1" -ForegroundColor White
        Write-Host ""
        Write-Host "Opening Ubuntu 24.04 now..." -ForegroundColor Green
        
        # Try to launch Ubuntu for setup
        Start-Process -FilePath "ubuntu2404.exe"
        exit 0
    }
} catch {
    Write-Error "Failed to test Ubuntu setup. Please ensure Ubuntu 24.04 is properly installed."
    exit 1
}

Write-Host "Ubuntu 24.04 is properly set up." -ForegroundColor Green

# Configure WinRM for Ansible connectivity
Write-Host "Configuring WinRM for Ansible connectivity..." -ForegroundColor Blue

# Set network connection to Private if it's Public (required for WinRM)
Write-Host "Checking network connection type..." -ForegroundColor Yellow
$networkProfiles = Get-NetConnectionProfile
foreach ($profile in $networkProfiles) {
    if ($profile.NetworkCategory -eq "Public") {
        Write-Host "Changing network '$($profile.Name)' from Public to Private..." -ForegroundColor Yellow
        Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private
        Write-Host "Network connection type changed to Private." -ForegroundColor Green
    } else {
        Write-Host "Network '$($profile.Name)' is already set to $($profile.NetworkCategory)." -ForegroundColor Green
    }
}

# Enable WinRM and configure for local network access
Write-Host "Enabling WinRM service..." -ForegroundColor Yellow
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Allow WinRM through Windows Firewall
Write-Host "Configuring Windows Firewall for WinRM..." -ForegroundColor Yellow
Set-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -Enabled True

# Configure WinRM for basic authentication (local development)
Write-Host "Configuring WinRM authentication..." -ForegroundColor Yellow
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'
winrm set winrm/config/client '@{AllowUnencrypted="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

# Configure TrustedHosts to allow local connections
Write-Host "Configuring TrustedHosts for local WinRM connections..." -ForegroundColor Yellow
winrm set winrm/config/client '@{TrustedHosts="localhost,127.0.0.1,192.168.*,10.*,172.16.*"}'

# Fix UAC elevation issues for Ansible/Packer over WinRM
Write-Host "Configuring LocalAccountTokenFilterPolicy for UAC elevation..." -ForegroundColor Yellow
$token_path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$token_prop_name = "LocalAccountTokenFilterPolicy"
$token_key = Get-Item -Path $token_path
$token_value = $token_key.GetValue($token_prop_name, $null)
if ($token_value -ne 1) {
    Write-Host "Setting LocalAccountTokenFilterPolicy to 1" -ForegroundColor Yellow
    if ($null -ne $token_value) {
        Remove-ItemProperty -Path $token_path -Name $token_prop_name
    }
    New-ItemProperty -Path $token_path -Name $token_prop_name -Value 1 -PropertyType DWORD > $null
    Write-Host "LocalAccountTokenFilterPolicy configured successfully." -ForegroundColor Green
} else {
    Write-Host "LocalAccountTokenFilterPolicy is already set to 1." -ForegroundColor Green
}

# Get the current user for WinRM access
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Current user for WinRM: $currentUser" -ForegroundColor Green

# Add current user to Remote Management Users group (required for domain users)
Write-Host "Adding current user to Remote Management Users group..." -ForegroundColor Yellow
try {
    $localUser = $env:USERNAME
    net localgroup "Remote Management Users" $currentUser /add 2>$null
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 2) {
        Write-Host "User added to Remote Management Users group successfully." -ForegroundColor Green
        
        # Restart WinRM service to apply group changes
        Write-Host "Restarting WinRM service to apply group membership changes..." -ForegroundColor Yellow
        Restart-Service WinRM -Force
        Start-Sleep -Seconds 3
        Write-Host "WinRM service restarted." -ForegroundColor Green
    } else {
        Write-Host "User may already be in the Remote Management Users group." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Note: Could not add user to Remote Management Users group: $_" -ForegroundColor Yellow
}

# Get Windows IP address that WSL can reach
$windowsIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "172.16.*" -or $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" }).IPAddress | Select-Object -First 1
if (-not $windowsIP) {
    $windowsIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }).IPAddress | Select-Object -First 1
}
Write-Host "Windows IP for WSL connection: $windowsIP" -ForegroundColor Green

# Clone the repository in WSL
$REPO_URL = "https://github.com/dyskette/.dotconfigs.git"

Write-Host "Setting up repository and Ansible in WSL..." -ForegroundColor Blue

# Create setup script for WSL
$wslSetupScript = @"
#!/bin/bash
set -e

echo "Updating package lists..."
sudo apt update

echo "Installing required packages..."
sudo apt install -y git python3 software-properties-common

echo "Adding Ansible PPA..."
sudo add-apt-repository --yes --update ppa:ansible/ansible

echo "Installing Ansible and Python WinRM support..."
sudo apt install -y ansible python3-winrm

echo "Configuring OpenSSL to support legacy algorithms (required for NTLM)..."
# Create OpenSSL configuration to enable MD4
sudo tee /etc/ssl/openssl_legacy.cnf > /dev/null << 'OPENSSL_CONF'
openssl_conf = openssl_init

[openssl_init]
providers = provider_sect

[provider_sect]
default = default_sect
legacy = legacy_sect

[default_sect]
activate = 1

[legacy_sect]
activate = 1
OPENSSL_CONF

# Set environment variable for OpenSSL configuration
echo 'export OPENSSL_CONF=/etc/ssl/openssl_legacy.cnf' | sudo tee -a /etc/environment
export OPENSSL_CONF=/etc/ssl/openssl_legacy.cnf

echo "Verifying installations..."
ansible --version
python3 -c "import winrm; print('python3-winrm installed successfully')"

# Handle repository setup
if [ ! -d "`$HOME/.dotconfigs" ]; then
    echo "Cloning repository from feature/windows-ansible branch..."
    git clone -b feature/windows-ansible $REPO_URL "`$HOME/.dotconfigs"
elif [ -d "`$HOME/.dotconfigs/.git" ]; then
    echo "Git repository already exists. Pulling latest changes..."
    cd "`$HOME/.dotconfigs"
    git checkout feature/windows-ansible 2>/dev/null || git checkout -b feature/windows-ansible origin/feature/windows-ansible
    git pull origin feature/windows-ansible
else
    echo "Directory exists but is not a git repository. Removing and cloning..."
    rm -rf "`$HOME/.dotconfigs"
    git clone -b feature/windows-ansible $REPO_URL "`$HOME/.dotconfigs"
fi

cd "`$HOME/.dotconfigs"

# Create Windows inventory file
echo "Creating Windows inventory configuration..."
cat > windows-ansible/inventory.yml << INVENTORY_EOF
windows_hosts:
  hosts:
    windows_target:
      ansible_host: WINDOWS_IP_PLACEHOLDER
      ansible_user: WINDOWS_USER_PLACEHOLDER
      ansible_password: WINDOWS_PASSWORD_PLACEHOLDER
      ansible_connection: winrm
      ansible_winrm_transport: ntlm
      ansible_winrm_server_cert_validation: ignore
      ansible_port: 5985
INVENTORY_EOF

echo "WSL setup completed successfully!"
echo "Ansible version: `$`(ansible --version | head -n1)"
echo "Windows target configured: WINDOWS_IP_PLACEHOLDER"
"@

# Get current user credentials for Windows access
Write-Host "Configuring credentials for Windows access..." -ForegroundColor Yellow
$windowsUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "You'll need to provide your Windows password for Ansible connectivity." -ForegroundColor Yellow
Write-Host "This will be stored temporarily for the setup process." -ForegroundColor Yellow
$securePassword = Read-Host "Enter your Windows password" -AsSecureString
$windowsPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))

# Replace variables in the setup script
$finalWslSetupScript = $wslSetupScript -replace 'WINDOWS_IP_PLACEHOLDER', $windowsIP -replace 'WINDOWS_USER_PLACEHOLDER', $windowsUser -replace 'WINDOWS_PASSWORD_PLACEHOLDER', $windowsPassword

# Write setup script to temporary file in a location accessible from WSL
$tempSetupScript = "$env:TEMP\wsl-setup.sh"
# Use Unix line endings (LF) and UTF8 without BOM for bash compatibility
$scriptLines = $finalWslSetupScript -split "`r?`n"
$unixScript = $scriptLines -join "`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tempSetupScript, $unixScript, $utf8NoBom)

# Convert Windows path to WSL path
$wslTempPath = $tempSetupScript -replace '^([A-Z]):', '/mnt/$1' -replace '\\', '/' 
$wslTempPath = $wslTempPath.ToLower()

Write-Host "Copying setup script to WSL..." -ForegroundColor Yellow
Write-Host "Windows path: $tempSetupScript" -ForegroundColor Gray
Write-Host "WSL path: $wslTempPath" -ForegroundColor Gray

# Copy the script to WSL temp directory and execute it
wsl --distribution Ubuntu-24.04 --exec bash -c "cp '$wslTempPath' /tmp/wsl-setup.sh && chmod +x /tmp/wsl-setup.sh && /tmp/wsl-setup.sh"

# Clean up temporary file
Remove-Item -Force $tempSetupScript

# Determine which tags to run
$tagsToRun = @()
if ($VSCode) {
    $tagsToRun += "vscode"
    Write-Host "Running VS Code installation only..." -ForegroundColor Yellow
}
if ($VSCodeExtensions) {
    $tagsToRun += "vscode-extensions"
    Write-Host "Running VS Code extensions installation only..." -ForegroundColor Yellow
}
if ($JetBrainsFont) {
    $tagsToRun += "jetbrains-font"
    Write-Host "Running JetBrains Mono Nerd Font installation only..." -ForegroundColor Yellow
}
if ($Chocolatey) {
    $tagsToRun += "chocolatey"
    Write-Host "Running Chocolatey installation only..." -ForegroundColor Yellow
}
if ($MinGW) {
    $tagsToRun += "mingw"
    Write-Host "Running MinGW installation only..." -ForegroundColor Yellow
}
if ($Deno) {
    $tagsToRun += "deno"
    Write-Host "Running Deno installation only..." -ForegroundColor Yellow
}
if ($CliTools) {
    $tagsToRun += "cli-tools"
    Write-Host "Running command-line tools installation only..." -ForegroundColor Yellow
}
if ($PowerShell) {
    $tagsToRun += "powershell"
    Write-Host "Running PowerShell Core installation only..." -ForegroundColor Yellow
}
if ($Fnm) {
    $tagsToRun += "fnm"
    Write-Host "Running fnm (Fast Node Manager) installation only..." -ForegroundColor Yellow
}
if ($Python) {
    $tagsToRun += "python"
    Write-Host "Running Python 3.12 installation only..." -ForegroundColor Yellow
}
if ($Neovim) {
    $tagsToRun += "neovim"
    Write-Host "Running Neovim installation only..." -ForegroundColor Yellow
}
if ($WindowsTerminal) {
    $tagsToRun += "windows-terminal"
    Write-Host "Running Windows Terminal installation only..." -ForegroundColor Yellow
}
if ($ProductivityApps) {
    $tagsToRun += "productivity-apps"
    Write-Host "Running productivity apps installation only..." -ForegroundColor Yellow
}
if ($Yazi) {
    $tagsToRun += "yazi"
    Write-Host "Running Yazi file manager installation only..." -ForegroundColor Yellow
}
if ($WindowsConfig) {
    $tagsToRun += "windows-config"
    Write-Host "Running Windows configuration only..." -ForegroundColor Yellow
}
if ($Configuration) {
    $tagsToRun += "configuration"
    Write-Host "Running all application configurations..." -ForegroundColor Yellow
}
if ($BatConfig) {
    $tagsToRun += "bat-config"
    Write-Host "Running bat configuration only..." -ForegroundColor Yellow
}
if ($PowerShellConfig) {
    $tagsToRun += "powershell-config"
    Write-Host "Running PowerShell configuration only..." -ForegroundColor Yellow
}
if ($StarshipConfig) {
    $tagsToRun += "starship-config"
    Write-Host "Running Starship configuration only..." -ForegroundColor Yellow
}
if ($NeovimConfig) {
    $tagsToRun += "neovim-config"
    Write-Host "Running Neovim configuration only..." -ForegroundColor Yellow
}
if ($VSCodeConfig) {
    $tagsToRun += "vscode-config"
    Write-Host "Running VS Code configuration only..." -ForegroundColor Yellow
}
if ($WindowsTerminalConfig) {
    $tagsToRun += "windows-terminal-config"
    Write-Host "Running Windows Terminal configuration only..." -ForegroundColor Yellow
}

# Build ansible-playbook command for WSL
$ansibleCmd = "cd ~/.dotconfigs && export OPENSSL_CONF=/etc/ssl/openssl_legacy.cnf && ansible-playbook -i windows-ansible/inventory.yml windows-ansible/playbook.yml"

# Add tags if specified
if ($tagsToRun.Count -gt 0) {
    $tagsString = $tagsToRun -join ","
    $ansibleCmd += " --tags $tagsString"
} elseif (-not $All) {
    # If no specific tags and not explicitly running all, show available options
    Write-Host ""
    Write-Host "Available options:" -ForegroundColor Green
    Write-Host "  -VSCode          : Install only VS Code application" -ForegroundColor White
    Write-Host "  -VSCodeExtensions: Install only VS Code extensions" -ForegroundColor White
    Write-Host "  -JetBrainsFont   : Install only JetBrains Mono Nerd Font" -ForegroundColor White
    Write-Host "  -Chocolatey      : Install only Chocolatey package manager" -ForegroundColor White
    Write-Host "  -MinGW           : Install only MinGW compiler" -ForegroundColor White
    Write-Host "  -Deno            : Install only Deno runtime" -ForegroundColor White
    Write-Host "  -CliTools        : Install command-line tools (make, wget, jq, fzf, etc.)" -ForegroundColor White
    Write-Host "  -PowerShell      : Install only PowerShell Core" -ForegroundColor White
    Write-Host "  -Fnm             : Install only fnm (Fast Node Manager)" -ForegroundColor White
    Write-Host "  -Python          : Install only Python 3.12" -ForegroundColor White
    Write-Host "  -Neovim          : Install only Neovim" -ForegroundColor White
    Write-Host "  -WindowsTerminal : Install only Windows Terminal" -ForegroundColor White
    Write-Host "  -ProductivityApps: Install productivity apps (Obsidian, Firefox, KeePassXC, Dropbox)" -ForegroundColor White
    Write-Host "  -Yazi            : Install only Yazi file manager" -ForegroundColor White
    Write-Host "  -WindowsConfig   : Configure Windows settings (Explorer, Virtual Desktops, etc.)" -ForegroundColor White
    Write-Host "  -Configuration   : Configure all applications (bat, PowerShell, Starship, Neovim, VS Code, Windows Terminal)" -ForegroundColor White
    Write-Host "  -BatConfig       : Configure bat" -ForegroundColor White
    Write-Host "  -PowerShellConfig: Configure PowerShell" -ForegroundColor White
    Write-Host "  -StarshipConfig  : Configure Starship" -ForegroundColor White
    Write-Host "  -NeovimConfig    : Configure Neovim" -ForegroundColor White
    Write-Host "  -VSCodeConfig    : Configure VS Code" -ForegroundColor White
    Write-Host "  -WindowsTerminalConfig: Configure Windows Terminal" -ForegroundColor White
    Write-Host "  -All             : Run all tasks (default)" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "Example usage:" -ForegroundColor Green
    Write-Host "  .\install.ps1 -VSCode" -ForegroundColor White
    Write-Host "  .\install.ps1 -VSCodeExtensions" -ForegroundColor White
    Write-Host "  .\install.ps1 -JetBrainsFont" -ForegroundColor White
    Write-Host "  .\install.ps1 -Chocolatey" -ForegroundColor White
    Write-Host "  .\install.ps1 -MinGW" -ForegroundColor White
    Write-Host "  .\install.ps1 -Deno" -ForegroundColor White
    Write-Host "  .\install.ps1 -CliTools" -ForegroundColor White
    Write-Host "  .\install.ps1 -PowerShell" -ForegroundColor White
    Write-Host "  .\install.ps1 -Fnm" -ForegroundColor White
    Write-Host "  .\install.ps1 -Python" -ForegroundColor White
    Write-Host "  .\install.ps1 -Neovim" -ForegroundColor White
    Write-Host "  .\install.ps1 -WindowsTerminal" -ForegroundColor White
    Write-Host "  .\install.ps1 -WindowsTerminal -PowerShell" -ForegroundColor White
    Write-Host "  .\install.ps1 -ProductivityApps" -ForegroundColor White
    Write-Host "  .\install.ps1 -Configuration" -ForegroundColor White
    Write-Host "  .\install.ps1 -VSCodeConfig -NeovimConfig" -ForegroundColor White
    Write-Host ""
    Write-Host "Running all tasks..." -ForegroundColor Yellow
}

# Add any additional arguments
if ($AdditionalArgs) {
    $ansibleCmd += " " + ($AdditionalArgs -join " ")
}

Write-Host "Testing WinRM connectivity from PowerShell first..." -ForegroundColor Blue

# Test WinRM connectivity using PowerShell first
Write-Host "Testing local WinRM connectivity..." -ForegroundColor Yellow
try {
    $testResult = Test-WSMan -ComputerName localhost -ErrorAction Stop
    Write-Host "PowerShell WinRM test to localhost: SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "PowerShell WinRM test to localhost: FAILED - $_" -ForegroundColor Red
}

try {
    $testResult = Test-WSMan -ComputerName $windowsIP -ErrorAction Stop
    Write-Host "PowerShell WinRM test to $windowsIP`: SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "PowerShell WinRM test to $windowsIP`: FAILED - $_" -ForegroundColor Red
}

Write-Host "Testing WinRM connectivity from WSL..." -ForegroundColor Blue

# Create Python test script with proper variable substitution
$escapedUser = $windowsUser -replace '\\', '\\\\'
$escapedPassword = $windowsPassword -replace "'", "\\'"
$localUsername = $env:USERNAME
$pythonTestScript = "import winrm`n"
$pythonTestScript += "import sys`n`n"
$pythonTestScript += "try:`n"
$pythonTestScript += "    print('Attempting WinRM connection...')`n"
$pythonTestScript += "    print('Target IP: $windowsIP`:5985')`n"
$pythonTestScript += "    print('Domain User: $escapedUser')`n"
$pythonTestScript += "    print('Local User: $localUsername')`n"
$pythonTestScript += "    `n"
$pythonTestScript += "    # Try different targets and authentication methods`n"
$pythonTestScript += "    session = None`n"
$pythonTestScript += "    auth_method = None`n"
$pythonTestScript += "    credentials_used = None`n"
$pythonTestScript += "    target_used = None`n"
$pythonTestScript += "    `n"
$pythonTestScript += "    # Try different target addresses: localhost, 127.0.0.1, actual IP`n"
$pythonTestScript += "    targets = ['127.0.0.1', 'localhost', '$windowsIP']`n"
$pythonTestScript += "    `n"
$pythonTestScript += "    for target in targets:`n"
$pythonTestScript += "        print(f'\\nTrying target: {target}:5985')`n"
$pythonTestScript += "        `n"
$pythonTestScript += "        # Method 1: Basic auth with local username (no domain)`n"
$pythonTestScript += "        try:`n"
$pythonTestScript += "            print(f'  Trying Basic auth with local username on {target}...')`n"
$pythonTestScript += "            session = winrm.Session(f'{target}:5985', auth=('$localUsername', '$escapedPassword'), transport='basic')`n"
$pythonTestScript += "            test_result = session.run_cmd('echo WinRM Basic local auth successful')`n"
$pythonTestScript += "            print(f'  SUCCESS: Basic authentication with local username on {target}!')`n"
$pythonTestScript += "            auth_method = 'basic'`n"
$pythonTestScript += "            credentials_used = 'local_username'`n"
$pythonTestScript += "            target_used = target`n"
$pythonTestScript += "            break`n"
$pythonTestScript += "        except Exception as basic_local_error:`n"
$pythonTestScript += "            print(f'  Basic auth with local username failed on {target}: {basic_local_error}')`n"
$pythonTestScript += "        `n"
$pythonTestScript += "        # Method 2: Basic auth with domain\\username`n"
$pythonTestScript += "        try:`n"
$pythonTestScript += "            print(f'  Trying Basic auth with domain\\\\username on {target}...')`n"
$pythonTestScript += "            session = winrm.Session(f'{target}:5985', auth=('$escapedUser', '$escapedPassword'), transport='basic')`n"
$pythonTestScript += "            test_result = session.run_cmd('echo WinRM Basic domain auth successful')`n"
$pythonTestScript += "            print(f'  SUCCESS: Basic authentication with domain\\\\username on {target}!')`n"
$pythonTestScript += "            auth_method = 'basic'`n"
$pythonTestScript += "            credentials_used = 'domain_username'`n"
$pythonTestScript += "            target_used = target`n"
$pythonTestScript += "            break`n"
$pythonTestScript += "        except Exception as basic_domain_error:`n"
$pythonTestScript += "            print(f'  Basic auth with domain\\\\username failed on {target}: {basic_domain_error}')`n"
$pythonTestScript += "        `n"
$pythonTestScript += "        # Method 3: NTLM with domain\\username`n"
$pythonTestScript += "        try:`n"
$pythonTestScript += "            print(f'  Trying NTLM auth with domain\\\\username on {target}...')`n"
$pythonTestScript += "            session = winrm.Session(f'{target}:5985', auth=('$escapedUser', '$escapedPassword'), transport='ntlm')`n"
$pythonTestScript += "            test_result = session.run_cmd('echo WinRM NTLM auth successful')`n"
$pythonTestScript += "            print(f'  SUCCESS: NTLM authentication with domain\\\\username on {target}!')`n"
$pythonTestScript += "            auth_method = 'ntlm'`n"
$pythonTestScript += "            credentials_used = 'domain_username'`n"
$pythonTestScript += "            target_used = target`n"
$pythonTestScript += "            break`n"
$pythonTestScript += "        except Exception as ntlm_error:`n"
$pythonTestScript += "            print(f'  NTLM auth failed on {target}: {ntlm_error}')`n"
$pythonTestScript += "    `n"
$pythonTestScript += "    # Check if any method succeeded`n"
$pythonTestScript += "    if session is None:`n"
$pythonTestScript += "        raise Exception('All authentication methods failed on all targets (127.0.0.1, localhost, $windowsIP)')`n"
$pythonTestScript += "    `n"
$pythonTestScript += "    # Run final test command`n"
$pythonTestScript += "    r = session.run_cmd('echo WinRM connection test successful')`n"
$pythonTestScript += "    print(f'Exit code: {r.status_code}')`n"
$pythonTestScript += "    print(f'Output: {r.std_out.decode().strip()}')`n"
$pythonTestScript += "    if r.std_err:`n"
$pythonTestScript += "        print(f'Error: {r.std_err.decode().strip()}')`n"
$pythonTestScript += "    if r.status_code == 0:`n"
$pythonTestScript += "        print(f'WinRM connection test passed using {auth_method} authentication with {credentials_used} on {target_used}!')`n"
$pythonTestScript += "        sys.exit(0)`n"
$pythonTestScript += "    else:`n"
$pythonTestScript += "        print('WinRM connection failed with non-zero exit code')`n"
$pythonTestScript += "        sys.exit(1)`n"
$pythonTestScript += "except Exception as e:`n"
$pythonTestScript += "    print(f'Connection failed: {e}')`n"
$pythonTestScript += "    import traceback`n"
$pythonTestScript += "    traceback.print_exc()`n"
$pythonTestScript += "    sys.exit(1)`n"

# Write test script to WSL accessible location
$tempTestScript = "$env:TEMP\winrm-test.py"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tempTestScript, $pythonTestScript, $utf8NoBom)

# Convert to WSL path and run the test
$wslTestPath = $tempTestScript -replace '^([A-Z]):', '/mnt/$1' -replace '\\', '/'
$wslTestPath = $wslTestPath.ToLower()

Write-Host "Testing connection with credentials: $windowsUser@$windowsIP" -ForegroundColor Gray
wsl --distribution Ubuntu-24.04 --exec bash -c "cd ~/.dotconfigs && export OPENSSL_CONF=/etc/ssl/openssl_legacy.cnf && python3 '$wslTestPath'"

if ($LASTEXITCODE -ne 0) {
    Write-Error "WinRM connection test failed. Please check credentials and WinRM configuration."
    Write-Host "Debug information:" -ForegroundColor Yellow
    Write-Host "  Windows IP: $windowsIP" -ForegroundColor White
    Write-Host "  Username: $windowsUser" -ForegroundColor White
    Write-Host "  Port: 5985" -ForegroundColor White
    Write-Host "  Transport: NTLM" -ForegroundColor White
    
    # Clean up test script and exit
    Remove-Item -Force $tempTestScript -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "WinRM connection test passed!" -ForegroundColor Green

# Clean up test script
Remove-Item -Force $tempTestScript -ErrorAction SilentlyContinue

Write-Host "Running Ansible playbook in WSL..." -ForegroundColor Cyan
Write-Host "Command: $ansibleCmd" -ForegroundColor Gray

# Execute ansible-playbook in WSL
wsl --distribution Ubuntu-24.04 --exec bash -c $ansibleCmd

# Clear sensitive variables
$windowsPassword = $null
$securePassword = $null

Write-Host ""
Write-Host "=== SETUP COMPLETE ===" -ForegroundColor Green
Write-Host "Your Windows development environment has been configured!" -ForegroundColor White
Write-Host "WSL Ubuntu 24.04 with Ansible is ready for future use." -ForegroundColor White
Write-Host ""
Write-Host "Connection Details:" -ForegroundColor Yellow
Write-Host "  Windows IP: $windowsIP" -ForegroundColor White
Write-Host "  Connection: WinRM (HTTP NTLM Auth)" -ForegroundColor White
Write-Host "  Port: 5985" -ForegroundColor White
Write-Host "  Inventory: windows-ansible/inventory.yml" -ForegroundColor White 