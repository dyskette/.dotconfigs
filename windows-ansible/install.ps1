#!/usr/bin/env pwsh

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

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Please run as Administrator."
    exit 1
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

# Check if Python is installed
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "Python not found. Installing Python..." -ForegroundColor Yellow
    
    # Install Python using winget
    winget install Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    
    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
} else {
    Write-Host "Python is already installed." -ForegroundColor Green
}

# Check if pip is available
if (-not (Get-Command pip -ErrorAction SilentlyContinue)) {
    Write-Error "pip not found. Please ensure Python is properly installed."
    exit 1
}

# Check if Ansible is installed
if (-not (Get-Command ansible-playbook -ErrorAction SilentlyContinue)) {
    Write-Host "Ansible not found. Installing..." -ForegroundColor Yellow
    
    # Upgrade pip first
    python -m pip install --upgrade pip
    
    # Install Ansible
    pip install ansible
    
    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
} else {
    Write-Host "Ansible is already installed." -ForegroundColor Green
}

# Clone the repository
$REPO_URL = "https://github.com/dyskette/.dotconfigs.git"
$DEST_DIR = "$env:USERPROFILE\.dotconfigs"

if (Test-Path $DEST_DIR) {
    Write-Host "Repository already exists. Pulling latest changes..." -ForegroundColor Blue
    Set-Location $DEST_DIR
    git pull
} else {
    Write-Host "Cloning repository..." -ForegroundColor Blue
    git clone $REPO_URL $DEST_DIR
    Set-Location $DEST_DIR
}

# Run Ansible playbook
if (-not (Test-Path "windows-ansible/playbook.yml")) {
    Write-Error "Playbook not found at windows-ansible/playbook.yml"
    exit 1
}

Write-Host "Running Ansible playbook..." -ForegroundColor Cyan

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

# Build ansible-playbook command
$ansibleArgs = @("-i", "windows-ansible/inventory.yml", "windows-ansible/playbook.yml")

# Add tags if specified
if ($tagsToRun.Count -gt 0) {
    $tagsString = $tagsToRun -join ","
    $ansibleArgs += "--tags"
    $ansibleArgs += $tagsString
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
    $ansibleArgs += $AdditionalArgs
}

# Execute ansible-playbook
& ansible-playbook @ansibleArgs 