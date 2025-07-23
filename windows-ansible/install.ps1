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

# Get the current user for WinRM access
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Current user for WinRM: $currentUser" -ForegroundColor Green

# Get Windows IP address that WSL can reach
$windowsIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "172.16.*" -or $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" }).IPAddress | Select-Object -First 1
if (-not $windowsIP) {
    $windowsIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }).IPAddress | Select-Object -First 1
}
Write-Host "Windows IP for WSL connection: $windowsIP" -ForegroundColor Green

# Clone the repository in WSL
$REPO_URL = "https://github.com/dyskette/.dotconfigs.git"
$DEST_DIR = "/home/\$USER/.dotconfigs"

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

echo "Installing Ansible via apt..."
sudo apt install -y ansible

# Install required Python packages for Windows management
echo "Installing Python packages for Windows connectivity..."
sudo apt install -y python3-pip
pip3 install --user pywinrm requests-ntlm

# Clone repository if it doesn't exist
if [ ! -d "$DEST_DIR" ]; then
    echo "Cloning repository..."
    git clone $REPO_URL $DEST_DIR
else
    echo "Repository already exists. Pulling latest changes..."
    cd $DEST_DIR
    git pull
fi

cd $DEST_DIR

# Create Windows inventory file
echo "Creating Windows inventory configuration..."
cat > windows-ansible/inventory.yml << 'INVENTORY_EOF'
windows_hosts:
  hosts:
    windows_target:
      ansible_host: $WINDOWS_IP
      ansible_user: $WINDOWS_USER
      ansible_password: $WINDOWS_PASSWORD
      ansible_connection: psrp
      ansible_psrp_protocol: http
      ansible_psrp_auth: basic
      ansible_psrp_cert_validation: ignore
INVENTORY_EOF

echo "WSL setup completed successfully!"
echo "Ansible version: \$(ansible --version | head -n1)"
echo "Windows target configured: $WINDOWS_IP"
"@

# Get current user credentials for Windows access
Write-Host "Configuring credentials for Windows access..." -ForegroundColor Yellow
$windowsUser = $env:USERNAME
Write-Host "You'll need to provide your Windows password for Ansible connectivity." -ForegroundColor Yellow
Write-Host "This will be stored temporarily for the setup process." -ForegroundColor Yellow
$securePassword = Read-Host "Enter your Windows password" -AsSecureString
$windowsPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))

# Replace variables in the setup script
$finalWslSetupScript = $wslSetupScript -replace '\$WINDOWS_IP', $windowsIP -replace '\$WINDOWS_USER', $windowsUser -replace '\$WINDOWS_PASSWORD', $windowsPassword

# Write setup script to temporary file
$tempSetupScript = "$env:TEMP\wsl-setup.sh"
$finalWslSetupScript | Out-File -FilePath $tempSetupScript -Encoding UTF8

# Copy setup script to WSL and execute it
Get-Content $tempSetupScript | wsl --distribution Ubuntu-24.04 --exec bash -c "cat > /tmp/wsl-setup.sh"
wsl --distribution Ubuntu-24.04 --exec chmod +x /tmp/wsl-setup.sh
wsl --distribution Ubuntu-24.04 --exec /tmp/wsl-setup.sh

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
$ansibleCmd = "cd $DEST_DIR && ansible-playbook -i windows-ansible/inventory.yml windows-ansible/playbook.yml"

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
Write-Host "  Connection: PSRP over WinRM" -ForegroundColor White
Write-Host "  Inventory: windows-ansible/inventory.yml" -ForegroundColor White 