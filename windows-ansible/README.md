# Windows Ansible Bootstrap

This directory contains scripts and playbooks to bootstrap Ansible on Windows using WSL (Windows Subsystem for Linux) and run configuration tasks.

## Prerequisites

- Windows 10 version 2004+ (Build 19041+) or Windows 11
- Administrator privileges
- Internet connection

## Architecture

The setup uses a modern approach:
1. **WSL (Windows Subsystem for Linux)** with Ubuntu 24.04 LTS
2. **Ansible** installed via official Ubuntu PPA for system integration
3. **WinRM/PSRP connectivity** from WSL to Windows host for remote management
4. **Playbooks** executed from WSL targeting Windows applications via WinRM
5. **PowerShell scripts** for Windows-specific configurations

This provides better compatibility with Ansible's Linux-native tooling while maintaining full Windows integration. The setup uses PowerShell Remoting (PSRP) over WinRM for reliable communication between WSL and Windows, which is the recommended approach for Windows automation.

## Quick Start

1. **Run as Administrator**: Open PowerShell as Administrator
2. **Execute the install script**:
   ```powershell
   # Download and run directly
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dyskette/.dotconfigs/master/windows-ansible/install.ps1" -OutFile "install.ps1"
   .\install.ps1
   
   # Or if you already have the repository cloned
   .\windows-ansible\install.ps1
   ```

## What the script does

1. **Checks for Administrator privileges** - Required for installing software and enabling WSL
2. **Verifies Windows version** - Ensures compatibility with modern WSL (Build 19041+)
3. **Installs winget** (if needed) - Windows package manager for subsequent installations
4. **Installs Git** (if not present) - Required for repository operations
5. **Installs WSL with Ubuntu 24.04** - Uses `wsl --install -d Ubuntu-24.04` for modern setup
6. **Configures WinRM** - Enables PowerShell Remoting and configures Windows for Ansible connectivity
7. **Sets up Ubuntu environment** - Installs Python 3, pywinrm, and required packages within WSL
8. **Installs Ansible** - Uses official Ubuntu PPA for system-integrated installation
9. **Creates dynamic inventory** - Configures Ansible to connect to Windows via PSRP/WinRM
10. **Clones/Updates repository** - Gets the latest dotconfigs within the WSL environment
11. **Runs the Ansible playbook** - Executes from WSL targeting Windows applications via WinRM
12. **Configures applications** - Sets up dotfiles and configurations for installed applications

### First Run vs. Subsequent Runs

**First Run** (WSL not installed):
- Installs WSL and Ubuntu 24.04
- Requires restart
- Ubuntu setup (username/password) after restart
- Re-run script to continue with Ansible setup

**Setup Run** (WSL installed, first Ansible setup):
- Configures WinRM on Windows
- Prompts for Windows user password (for Ansible connectivity)
- Sets up Ansible environment in WSL
- Creates dynamic inventory with connection details

**Subsequent Runs** (WSL already set up):
- Direct execution of selected tasks
- No restart required

## Ansible Environment

After installation, you'll have Ansible ready to use in WSL:

### Installed Tools
- **Python 3** - Latest version from Ubuntu 24.04 repositories
- **Ansible** - Automation and configuration management (via official PPA)
- **pywinrm** - Python library for Windows Remote Management connectivity
- **Git** - Version control and repository management

### Connection Details
- **Protocol**: PowerShell Remoting (PSRP) over WinRM
- **Authentication**: Basic authentication over HTTP (local network)
- **Target**: Windows host from WSL environment
- **Inventory**: Dynamically generated with Windows IP and credentials

### Using Ansible

```bash
# Access WSL Ubuntu environment
wsl

# Check Ansible installation
ansible --version
ansible-playbook --version

# Run playbooks (from repository directory)
cd ~/.dotconfigs
ansible-playbook -i windows-ansible/inventory.yml windows-ansible/playbook.yml

# Run with specific tags
ansible-playbook -i windows-ansible/inventory.yml windows-ansible/playbook.yml --tags "vscode,configuration"

# Update Ansible
sudo apt update
sudo apt upgrade ansible
```

### Managing the Installation

```bash
# Update Ansible through system package manager
sudo apt update && sudo apt upgrade

# Check available Ansible versions
apt list --upgradable | grep ansible

# Remove Ansible if needed
sudo apt remove ansible
```

## Files

- `install.ps1` - Main bootstrap script
- `inventory.yml` - Ansible inventory for localhost
- `playbook.yml` - Main configuration playbook
- `Install-JetBrainsFont.ps1` - PowerShell script for JetBrains font installation
- `Update-ChocolateyEnvironment.ps1` - PowerShell script for Chocolatey environment setup
- `Setup-NodeLTS.ps1` - PowerShell script for Node.js LTS setup via fnm
- `Configure-WindowsSettings.ps1` - PowerShell script for Windows system configuration
- `Configure-Bat.ps1` - PowerShell script for bat configuration with themes
- `Configure-PowerShell.ps1` - PowerShell script for PowerShell profile configuration
- `Configure-Starship.ps1` - PowerShell script for Starship prompt configuration
- `Configure-Neovim.ps1` - PowerShell script for Neovim configuration
- `Configure-VSCode.ps1` - PowerShell script for VS Code settings and keybindings configuration
- `Configure-WindowsTerminal.ps1` - PowerShell script for Windows Terminal configuration
- `README.md` - This file

## Selective Execution

You can run specific parts of the configuration:

```powershell
# Install only VS Code application
.\install.ps1 -VSCode

# Install only VS Code extensions
.\install.ps1 -VSCodeExtensions

# Install only JetBrains Mono Nerd Font
.\install.ps1 -JetBrainsFont

# Install only Chocolatey package manager
.\install.ps1 -Chocolatey

# Install only MinGW compiler
.\install.ps1 -MinGW

# Install only Deno runtime
.\install.ps1 -Deno

# Install command-line tools (make, wget, jq, fzf, etc.)
.\install.ps1 -CliTools

# Install only PowerShell Core
.\install.ps1 -PowerShell

# Install only fnm (Fast Node Manager)
.\install.ps1 -Fnm

# Install only Python 3.12
.\install.ps1 -Python

# Install only Neovim
.\install.ps1 -Neovim

# Install only Windows Terminal
.\install.ps1 -WindowsTerminal

# Install productivity apps (Obsidian, Firefox, KeePassXC, Dropbox)
.\install.ps1 -ProductivityApps

# Install only Yazi file manager
.\install.ps1 -Yazi

# Configure Windows settings only
.\install.ps1 -WindowsConfig

# Configure all applications
.\install.ps1 -Configuration

# Configure specific applications
.\install.ps1 -BatConfig
.\install.ps1 -PowerShellConfig
.\install.ps1 -StarshipConfig
.\install.ps1 -NeovimConfig
.\install.ps1 -VSCodeConfig
.\install.ps1 -WindowsTerminalConfig

# Install multiple components
.\install.ps1 -VSCode -VSCodeExtensions
.\install.ps1 -VSCode -JetBrainsFont
.\install.ps1 -VSCode -Chocolatey
.\install.ps1 -VSCode -Deno
.\install.ps1 -Neovim -JetBrainsFont
.\install.ps1 -WindowsTerminal -PowerShell
.\install.ps1 -Python -Fnm
.\install.ps1 -VSCode -WindowsConfig
.\install.ps1 -VSCode -VSCodeExtensions -JetBrainsFont -Chocolatey -MinGW -Deno -CliTools -PowerShell -Fnm -Python -Neovim -WindowsTerminal -ProductivityApps -Yazi -WindowsConfig

# Run all tasks (default behavior)
.\install.ps1 -All
```

## Usage with additional arguments

You can pass additional arguments to the ansible-playbook command:

```powershell
# Run with verbose output
.\install.ps1 -VSCode -v

# Run terminal installation with extra variables
.\install.ps1 -WindowsTerminal --extra-vars "key=value"

# Run complete development setup with verbose output
.\install.ps1 -VSCode -Chocolatey -MinGW -Deno -CliTools -PowerShell -Fnm -Python -Neovim -WindowsTerminal -ProductivityApps -WindowsConfig -vv

# Run all tasks with very verbose output
.\install.ps1 -All -vvv

# Complete setup with configurations
.\install.ps1 -VSCode -VSCodeExtensions -VSCodeConfig -JetBrainsFont -Chocolatey -MinGW -Deno -CliTools -PowerShell -PowerShellConfig -Fnm -Python -Neovim -NeovimConfig -WindowsTerminal -WindowsTerminalConfig -ProductivityApps -Yazi -WindowsConfig -BatConfig -StarshipConfig

# Install and configure everything
.\install.ps1 -All -Configuration
```

## Customization

### Editing Configuration

The setup uses a modular approach for better maintainability:

- **`playbook.yml`** - Edit to add new Ansible tasks and configuration
- **`Install-JetBrainsFont.ps1`** - Edit PowerShell font installation logic with full syntax highlighting
- **`Update-ChocolateyEnvironment.ps1`** - Edit PowerShell Chocolatey environment setup with full syntax highlighting
- **`Setup-NodeLTS.ps1`** - Edit PowerShell Node.js LTS setup via fnm with full syntax highlighting
- **`Configure-WindowsSettings.ps1`** - Edit PowerShell Windows system configuration with full syntax highlighting

### Current Playbook Components

- **VS Code installation** (tags: `vscode`, `apps`)
- **VS Code extensions** (tags: `vscode-extensions`, `extensions`)
- **JetBrains Mono Nerd Font** (tags: `jetbrains-font`, `fonts`)
- **Chocolatey package manager** (tags: `chocolatey`, `package-managers`)
- **MinGW compiler** (tags: `mingw`, `development`, `compilers`)
- **Deno runtime** (tags: `deno`, `development`, `runtimes`)
- **Command-line tools** (tags: `cli-tools`, `utilities`, `development`)
  - Make, Wget, Difftastic, Less, jq, yq, fzf, fd, eza, ripgrep, bat, FFmpeg, Starship
- **PowerShell Core** (tags: `powershell`, `shells`, `development`)
- **fnm (Fast Node Manager)** (tags: `fnm`, `development`, `version-managers`)
  - Automatically installs Node.js LTS and sets it as default
- **Python 3.12** (tags: `python`, `development`, `runtimes`)
- **Neovim** (tags: `neovim`, `editors`, `development`)
- **Windows Terminal** (tags: `windows-terminal`, `terminals`, `apps`)
- **Productivity applications** (tags: `productivity-apps`, `apps`, `utilities`)
  - Obsidian, Firefox, KeePassXC, Dropbox
- **Yazi file manager** (tags: `yazi`, `cli-tools`, `file-manager`)
- **Windows configuration** (tags: `windows-config`, `system-settings`, `configuration`)
  - Enable file extensions and hidden files in Explorer
  - Configure virtual desktop behavior (taskbar and Alt+Tab)
  - Optimize browser Alt+Tab behavior

### Application Configuration Tasks

- **Bat configuration** (tags: `bat-config`, `configuration`, `cli-tools`)
  - Creates junction from repository bat config to `%APPDATA%\bat`
  - Builds bat cache for syntax highlighting themes
- **PowerShell configuration** (tags: `powershell-config`, `configuration`, `shells`)
  - Creates junction from repository PowerShell profile to `Documents\PowerShell`
  - Includes Starship integration, fnm environment, and custom aliases
- **Starship configuration** (tags: `starship-config`, `configuration`, `cli-tools`)
  - Creates junction from repository Starship config to `%USERPROFILE%\.config\starship`
  - Sets STARSHIP_CONFIG environment variable
  - Includes multiple color palette themes (Gruvbox, Rose Pine Dawn, Kanagawa, Everforest)
- **Neovim configuration** (tags: `neovim-config`, `configuration`, `editors`)
  - Creates junction from repository nvim config to `%LOCALAPPDATA%\nvim`
  - Full Neovim configuration with plugins, LSP, and keybindings
- **VS Code configuration** (tags: `vscode-config`, `configuration`, `editors`)
  - Creates symbolic links for settings.json and keybindings.json to `%APPDATA%\Code\User`
  - Includes theme switching, font configuration, and editor preferences
- **Windows Terminal configuration** (tags: `windows-terminal-config`, `configuration`, `terminals`)
  - Creates symbolic link for settings.json to Windows Terminal LocalState directory
  - Includes color schemes, font configuration, and shell profiles

### Adding New Tasks

When adding new tasks, use tags to organize them:

```yaml
- name: Install Another App
  ansible.windows.win_command: winget install SomeApp
  tags:
    - apps
    - someapp

- name: Run Custom PowerShell Script
  ansible.windows.win_powershell:
    script: "{{ playbook_dir }}/windows-ansible/Your-Script.ps1"
  tags:
    - custom
    - scripts

- name: Install Another Development Tool
  ansible.windows.win_command: choco install some-dev-tool --yes
  tags:
    - development
    - compilers
```

### Editing PowerShell Scripts

For complex PowerShell logic, create separate `.ps1` files in the `windows-ansible/` directory. This provides:
- **Proper syntax highlighting** in your editor
- **Language server support** (IntelliSense, error checking)
- **Easier debugging and testing**
- **Reusability** across different tasks

## Troubleshooting

### WSL Related Issues

- **WSL installation fails**: 
  - Ensure Windows version is 2004+ (Build 19041+)
  - Check if virtualization is enabled in BIOS
  - Run Windows Update to get latest features
  
- **Ubuntu setup required**: 
  - Open Ubuntu 24.04 from Start menu
  - Complete username/password setup
  - Re-run the install script

- **WSL command not found**: 
  - Restart after WSL installation
  - Check Windows features: `wsl --status`

### General Issues

- **Permission errors**: Ensure you're running PowerShell as Administrator
- **Git not found**: Install Git from [git-scm.com](https://git-scm.com) or use winget
- **Ansible not found in WSL**: The script installs Ansible via apt, check installation: `ansible --version`
- **Ansible PPA issues**: Verify PPA was added correctly: `sudo apt-cache policy ansible`
- **WinRM connection issues**: 
  - Verify WinRM is running: `winrm quickconfig` in Windows PowerShell
  - Check Windows IP is reachable from WSL: `wsl -e ping <windows_ip>`
  - Test WinRM connectivity: `wsl -e ansible windows_target -m win_ping`
- **Authentication failures**: 
  - Ensure Windows password is correct
  - Check if user account has necessary permissions
  - Verify basic authentication is enabled: `winrm get winrm/config`
- **Network issues**: Check firewall settings and proxy configuration

### WSL Specific Commands

```powershell
# Check WSL status
wsl --status

# List installed distributions
wsl --list --verbose

# Set Ubuntu as default
wsl --set-default Ubuntu-24.04

# Access Ubuntu environment
wsl --distribution Ubuntu-24.04

# Reset Ubuntu installation (if needed)
wsl --unregister Ubuntu-24.04

# Check Ansible installation within WSL
wsl -e ansible --version

# Test Windows connectivity from WSL
wsl -e ansible windows_target -m win_ping

# Check inventory configuration
wsl -e cat ~/.dotconfigs/windows-ansible/inventory.yml

# Access WSL to troubleshoot Ansible
wsl
``` 