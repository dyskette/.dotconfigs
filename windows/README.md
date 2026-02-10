# Windows Development Environment Setup

Automated Windows development environment configuration using **winget** for all package installation and PowerShell scripts for dotfile linking and system configuration.

## Quick Start

On a fresh Windows install, paste this into PowerShell (no git or winget needed):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iwr 'https://raw.githubusercontent.com/dyskette/.dotconfigs/master/windows/Bootstrap.ps1' -UseBasicParsing | iex
```

This downloads the repo, runs the full setup, and converts the directory into a git clone afterward.

If the repo is already cloned:

```powershell
# Run as Administrator — installs and configures everything
.\Install-WindowsEnvironment.ps1

# Skip specific phases
.\Install-WindowsEnvironment.ps1 -SkipWSL
.\Install-WindowsEnvironment.ps1 -SkipPackages -SkipFont
```

## What Gets Installed

### Packages (all via winget, declared in `packages.jsonc`)

| Category | Packages |
|----------|----------|
| **Editors** | VS Code, Neovim |
| **Languages** | Python 3.12, Deno, fnm (Node.js) |
| **Compilers** | WinLibs (GCC/MinGW-w64 + GDB + Make + CMake) |
| **CLI Tools** | make, wget, jq, yq, fzf, fd, eza, ripgrep, bat, less, yazi, ffmpeg |
| **Shell** | PowerShell Core, Starship prompt |
| **Terminals** | Windows Terminal, WezTerm |
| **Apps** | Firefox, Obsidian, KeePassXC, Dropbox |

### System Configuration
- **WSL** with Ubuntu 24.04 LTS + HiDPI `.wslgconfig`
- **JetBrains Mono NL Nerd Font**
- **Windows Explorer** — show file extensions, show hidden files
- **Virtual Desktops** — unified taskbar and Alt+Tab across desktops
- **Editor extensions** for VS Code (from `vscode/extensions.json`)
- **Node.js LTS** via fnm

### Dotfile Links (managed by `Configure-Dotfiles.ps1`)

| App | Source | Target | Type |
|-----|--------|--------|------|
| nvim | `nvim/` | `$LOCALAPPDATA\nvim` | Junction |
| powershell | `powershell/` | `$HOME\Documents\PowerShell` | Junction |
| bat | `bat/` | `$APPDATA\bat` | Junction |
| starship | `starship/` | `$HOME\.config\starship` | Junction |
| bash | `bash/bashrc` | `$HOME\.bashrc` | Symlink |
| bash | `bash/bashrc.d/` | `$HOME\.bashrc.d` | Junction |
| vscode | `vscode/*.json` | `$APPDATA\Code\User\` | Symlink |
| windows-terminal | `windows_terminal/settings.json` | Terminal LocalState | Symlink |
| wezterm | `wezterm/*.lua` | `$HOME\.config\wezterm\` | Symlink |
| zed | `zed/*.json` | `$APPDATA\Zed\` | Symlink |

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-SkipWSL` | Skip WSL installation |
| `-SkipPackages` | Skip winget package installation |
| `-SkipConfiguration` | Skip dotfile linking |
| `-SkipExtensions` | Skip editor extension installation |
| `-SkipFont` | Skip JetBrains Mono Nerd Font |
| `-SkipNodeSetup` | Skip Node.js LTS setup via fnm |
| `-SkipWindowsSettings` | Skip Windows registry settings |

## Script Files

| File | Description |
|------|-------------|
| `Bootstrap.ps1` | One-liner entry point for fresh installs |
| `Install-WindowsEnvironment.ps1` | Main orchestrator |
| `packages.jsonc` | Winget package manifest |
| `Setup-PackageManagers.ps1` | Bootstraps/updates winget |
| `Configure-Dotfiles.ps1` | Data-driven symlink/junction table |
| `Configure-WindowsSettings.ps1` | Windows registry tweaks |
| `Install-WSL.ps1` | WSL + Ubuntu 24.04 setup |
| `Install-Extensions.ps1` | VS Code extensions |
| `Install-JetBrainsFont.ps1` | Nerd Font installation |
| `Setup-NodeLTS.ps1` | Node.js LTS via fnm |

## Running Individual Scripts

```powershell
# Configure only dotfiles
.\Configure-Dotfiles.ps1

# Configure specific apps only
.\Configure-Dotfiles.ps1 -Filter nvim, vscode, bat

# Install VS Code extensions
.\Install-Extensions.ps1

# Bootstrap winget
.\Setup-PackageManagers.ps1
```

## Requirements

- Windows 10 version 2004+ (Build 19041+) or Windows 11
- Administrator privileges
- Internet connection
