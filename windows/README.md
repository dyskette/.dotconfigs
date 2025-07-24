# Windows Development Environment Setup

Automated Windows development environment configuration using **winget and Chocolatey** - a hybrid approach that uses the best package manager for each application.

## Overview

This script uses a hybrid approach that automatically chooses the best package manager for each application:

- ✅ Uses **winget** for most packages (Microsoft's official package manager)
- ✅ Uses **chocolatey** for specific packages (like MinGW) where it's better suited
- ✅ Simple and straightforward - no unnecessary complexity
- ✅ Automatic package manager selection - you don't need to choose
- ✅ Sets up WSL with Ubuntu 24.04 for future use (but doesn't depend on it)
- ✅ Provides granular control over what gets installed
- ✅ Includes comprehensive configuration management

## Quick Start

### Install Everything (Recommended)
```powershell
# Run as Administrator
.\install.ps1
```

### Install Specific Components
```powershell
# Install only VS Code and extensions
.\install.ps1 -VSCode -VSCodeExtensions

# Install development tools
.\install.ps1 -CliTools -PowerShell -Neovim

# Install productivity apps
.\install.ps1 -ProductivityApps
```

## What Gets Installed

### Development Tools
- **VS Code** (winget) with extensions from `vscode/extensions.json` (GitLens, Vim, themes, language support)
- **PowerShell Core** (winget) with profile configuration
- **Neovim** (winget) with dotfile configuration
- **Python 3.12** (winget) with pip
- **Deno** (winget) runtime
- **fnm** (winget) Fast Node Manager with Node.js LTS
- **MinGW** (chocolatey) compiler toolchain

### Command Line Utilities (all via winget)
- **make, wget, jq, yq** - Essential CLI tools
- **fzf, fd, eza, ripgrep** - Modern file search and navigation
- **bat, less** - Enhanced file viewing
- **Starship** - Modern shell prompt
- **Yazi** - Terminal file manager
- **FFmpeg** - Media processing

### Applications (all via winget)
- **Windows Terminal** with configuration
- **Firefox** browser
- **Obsidian** note-taking
- **KeePassXC** password manager
- **Dropbox** cloud storage

### System Configuration
- **WSL** with Ubuntu 24.04 LTS (for future use)
- **Windows Explorer** settings (show file extensions, hidden files)
- **Virtual Desktop** settings (unified taskbar and Alt+Tab)
- **JetBrains Mono Nerd Font** installation

## Available Parameters

| Parameter | Description |
|-----------|-------------|
| `-VSCode` | Install VS Code application only |
| `-VSCodeExtensions` | Install VS Code extensions only |
| `-JetBrainsFont` | Install JetBrains Mono Nerd Font only |
| `-MinGW` | Install MinGW compiler only |
| `-Deno` | Install Deno runtime only |
| `-CliTools` | Install command-line tools only |
| `-PowerShell` | Install PowerShell Core only |
| `-Fnm` | Install fnm (Fast Node Manager) only |
| `-Python` | Install Python 3.12 only |
| `-Neovim` | Install Neovim only |
| `-WindowsTerminal` | Install Windows Terminal only |
| `-ProductivityApps` | Install productivity apps only |
| `-Yazi` | Install Yazi file manager only |
| `-WindowsConfig` | Configure Windows settings only |
| `-Configuration` | Run all application configurations |
| `-PowerShellConfig` | Configure PowerShell only |
| `-SkipWSL` | Skip WSL installation entirely |
| `-All` | Install and configure everything (default) |

## Examples

```powershell
# Install just the essentials for development
.\install.ps1 -VSCode -PowerShell -CliTools

# Setup a complete development environment
.\install.ps1 -All

# Install and configure specific tools
.\install.ps1 -Neovim -NeovimConfig

# Install productivity applications only
.\install.ps1 -ProductivityApps

# Configure Windows settings without installing anything
.\install.ps1 -WindowsConfig

# Install everything except WSL
.\install.ps1 -All -SkipWSL
```

## Requirements

- Windows 10 version 2004+ (Build 19041+) or Windows 11
- Administrator privileges
- Internet connection
- No additional dependencies required

## How It Works

1. **Package Managers Setup**: Automatically installs and configures winget and chocolatey
2. **WSL Features**: Enables Windows Subsystem for Linux and Virtual Machine Platform features (with restart if needed)
3. **WSL Setup**: Installs WSL with Ubuntu 24.04 (for future use, not used by the script)
4. **Package Installation**: Automatically uses winget or chocolatey for each package based on optimal compatibility
5. **Configuration**: Applies dotfile configurations and Windows settings
6. **Modular Execution**: Each component runs independently with clear status reporting

## Benefits Over Previous Approach

- **Hybrid Approach**: Uses winget (official) and chocolatey where each excels
- **Intelligent Selection**: Automatically chooses the best package manager for each app
- **More Reliable**: Uses Microsoft's official winget for most packages
- **KISS Principle**: Keep It Simple, Stupid - straightforward approach
- **Better Error Handling**: Clear success/failure reporting for each package
- **Modular Architecture**: Each component is separated for better maintainability
- **Standalone Scripts**: Individual scripts can be run independently
- **Flexible Configuration**: Mix and match components as needed
- **Centralized Configuration**: Extensions and settings sourced from dotfiles configuration
- **Future-Proof**: Uses modern Windows package management approach

## Troubleshooting

### Common Issues

**Execution Policy Error**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Package Installation Fails**
- Check your internet connection
- Ensure winget is working: `winget --version`
- Ensure chocolatey is working: `choco --version`
- Try running the package managers setup: `.\Setup-PackageManagers.ps1`
- Try installing individual packages manually:
  - Winget: `winget install --exact --id PackageId`
  - Chocolatey: `choco install package-name -y`
- Run Windows Update before running the script

**Permission Issues**
- Ensure you're running PowerShell as Administrator
- Some packages may require additional permissions

**WSL Installation Fails**
- The script automatically enables required Windows features (WSL and Virtual Machine Platform)
- If features need to be enabled, a restart will be required before WSL installation can proceed
- Run the script again after restart to continue with Ubuntu installation

### Manual Package Installation

If the automated installation fails, you can install packages manually:

```powershell
# Install Chocolatey first
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Then install packages
choco install vscode neovim powershell-core -y
```

## Script Files

| File | Description |
|------|-------------|
| `install.ps1` | Main installation orchestrator (modular approach) |
| `Setup-PackageManagers.ps1` | Sets up winget and chocolatey package managers |
| `Install-WSL.ps1` | Dedicated WSL installation and feature enablement |
| `Install-Packages.ps1` | Hybrid package installation (winget + chocolatey) |
| `Install-VSCodeExtensions.ps1` | VS Code extensions from ../vscode/extensions.json |
| `Install-JetBrainsFont.ps1` | JetBrains Mono Nerd Font installation |
| `Setup-NodeLTS.ps1` | Node.js LTS setup via fnm |
| `Configure-WindowsSettings.ps1` | Windows Explorer and system settings |
| `Configure-PowerShell.ps1` | PowerShell profile configuration |
| `Configure-Bat.ps1` | Bat syntax highlighter configuration |
| `Configure-Starship.ps1` | Starship prompt configuration |
| `Configure-Neovim.ps1` | Neovim editor configuration |
| `Configure-VSCode.ps1` | VS Code settings configuration |
| `Configure-WindowsTerminal.ps1` | Windows Terminal configuration |
| `Update-ChocolateyEnvironment.ps1` | Chocolatey environment configuration |

### Modular Script Architecture

The installation system now uses a modular approach where each component is separated into its own script. The main `install.ps1` orchestrates these scripts based on parameters.

#### Package Installation (Standalone)
```powershell
# Install all packages via hybrid approach (winget + chocolatey)
.\Install-Packages.ps1 -All

# Install specific package categories (automatically uses best package manager)
.\Install-Packages.ps1 -CliTools -PowerShell -VSCode

# Install just development tools (MinGW uses chocolatey, others use winget)
.\Install-Packages.ps1 -MinGW -Deno -Python -Neovim
```

#### Package Managers Setup (Standalone)
```powershell
# Setup both winget and chocolatey
.\Setup-PackageManagers.ps1

# Force reinstall of package managers
.\Setup-PackageManagers.ps1 -Force
```

#### VS Code Extensions (Standalone)
```powershell
# Install extensions from ../vscode/extensions.json
.\Install-VSCodeExtensions.ps1

# Install custom extensions only (skip extensions.json)
.\Install-VSCodeExtensions.ps1 -Extensions @("ms-python.python", "rust-lang.rust-analyzer") -CustomOnly

# Force reinstall all extensions
.\Install-VSCodeExtensions.ps1 -Force

# Install both default (from extensions.json) and custom extensions
.\Install-VSCodeExtensions.ps1 -Extensions @("github.copilot", "ms-vscode.remote-ssh")
```

#### WSL Installation (Standalone)
```powershell
# Run WSL installation independently
.\Install-WSL.ps1

# Enable features only (without installing Ubuntu)
.\Install-WSL.ps1 -FeaturesOnly

# Enable features and force restart
.\Install-WSL.ps1 -FeaturesOnly -ForceRestart
```

#### Configuration Scripts (Standalone)
```powershell
# Configure individual applications
.\Configure-PowerShell.ps1
.\Configure-Starship.ps1
.\Configure-Neovim.ps1
.\Configure-VSCode.ps1
.\Configure-WindowsTerminal.ps1
.\Configure-WindowsSettings.ps1

# Install and configure fonts
.\Install-JetBrainsFont.ps1

# Setup Node.js LTS
.\Setup-NodeLTS.ps1
```

## Contributing

This script is part of a larger dotfiles repository. Feel free to customize the package list and configurations to match your needs.

## License

This project is part of the `.dotconfigs` repository and follows the same licensing terms. 