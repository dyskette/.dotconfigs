# Windows Ansible Bootstrap

This directory contains scripts and playbooks to bootstrap Ansible on Windows and run configuration tasks.

## Prerequisites

- Windows 10/11 with PowerShell 5.1 or PowerShell Core 7+
- Administrator privileges
- Internet connection

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

1. **Checks for Administrator privileges** - Required for installing software
2. **Installs Python** (if not present) - Using winget package manager
3. **Installs Ansible** - Via Python pip
4. **Clones/Updates repository** - Gets the latest dotconfigs
5. **Runs the Ansible playbook** - Executes the configuration tasks
6. **Configures applications** - Sets up dotfiles and configurations for installed applications

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

- **Python installation fails**: Install Python manually from [python.org](https://python.org)
- **Ansible not found**: Restart PowerShell after installation to refresh PATH
- **Permission errors**: Ensure you're running as Administrator
- **Git not found**: Install Git from [git-scm.com](https://git-scm.com) 