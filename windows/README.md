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

# Opt in / skip specific phases
.\Install-WindowsEnvironment.ps1 -InstallWSL
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
| **.NET** | SDK 6, 7, 8, 9 (SDK 10 comes with Visual Studio) |
| **Databases** | sqlcmd, SQLcl, psql (`Install-Psql.ps1`), SQL*Plus (`Install-SqlPlus.ps1`) |
| **Cloud** | Azure CLI, Azure Functions Core Tools, Aspire CLI, Terraform |
| **AI** | OpenCode CLI (`Install-OpenCode.ps1`, not on winget) |
| **Shell** | PowerShell Core |
| **Terminals** | Windows Terminal |
| **Apps** | Firefox, Obsidian, KeePassXC, Dropbox |

### System Configuration
- **WSL** with Ubuntu 24.04 LTS + HiDPI `.wslgconfig`
- **JetBrains Mono NL Nerd Font**
- **Windows Explorer** — show file extensions, show hidden files
- **Virtual Desktops** — unified taskbar and Alt+Tab across desktops
- **Editor extensions** for VS Code (from `vscode/extensions.json`) and Visual Studio (from `vs/extensions.jsonc`)
- **Node.js LTS** via fnm

### Dotfile Links (managed by `Configure-Dotfiles.ps1`)

| App | Source | Target | Type |
|-----|--------|--------|------|
| nvim | `nvim/` | `$LOCALAPPDATA\nvim` | Junction |
| lazygit | `lazygit/config.yml` | `$LOCALAPPDATA\lazygit\config.yml` | Symlink |
| powershell | `powershell/` | `$HOME\Documents\PowerShell` | Junction |
| bat | `bat/` | `$APPDATA\bat` | Junction |
| bash | `bash/bashrc` | `$HOME\.bashrc` | Symlink |
| bash | `bash/bashrc.d/` | `$HOME\.bashrc.d` | Junction |
| claude | `claude/settings.json` | `$HOME\.claude\settings.json` | Symlink |
| opencode | `opencode/` | `$HOME\.config\opencode` | Junction |
| tmux | `tmux/psmux.conf` | `$HOME\.psmux.conf` | Symlink |
| vs | `vs/vsvimrc` | `$HOME\.vsvimrc` | Symlink |
| vscode | `vscode/settings.json` | `$APPDATA\Code\User\settings.json` | Symlink |
| vscode | `vscode/keybindings.json` | `$APPDATA\Code\User\keybindings.json` | Symlink |
| windows-terminal | `windows_terminal/settings.json` | `$LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` | Symlink |
| yazi | `yazi/` | `$APPDATA\yazi\config` | Junction |
| zellij | `zellij/` | `$APPDATA\zellij\config` | Junction |
| zed | `zed/settings.json` | `$APPDATA\Zed\settings.json` | Hard link |
| zed | `zed/keymap.json` | `$APPDATA\Zed\keymap.json` | Hard link |

`Configure-Dotfiles.ps1` also creates `$HOME\.local\bin` and adds it to the user
PATH, under the `localbin` filter name. Linking `bat` rebuilds its theme cache
and linking `yazi` restores its packages with `ya pkg install`.

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-InstallWSL` | Install WSL with Ubuntu 24.04 (opt-in, off by default) |
| `-SkipPackages` | Skip winget package installation |
| `-SkipConfiguration` | Skip dotfile linking |
| `-SkipExtensions` | Skip editor extension installation |
| `-SkipFont` | Skip JetBrains Mono Nerd Font |
| `-SkipNodeSetup` | Skip Node.js LTS setup via fnm |
| `-SkipOpenCode` | Skip the OpenCode CLI installation |
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
| `Install-Extensions.ps1` | VS Code and Visual Studio extensions |
| `Install-JetBrainsFont.ps1` | Nerd Font installation |
| `Setup-NodeLTS.ps1` | Node.js LTS via fnm |
| `Install-Psql.ps1` | PostgreSQL command line tools (psql) only, no server |
| `Install-SqlPlus.ps1` | Oracle SQL*Plus from the Instant Client zips (not on winget) |
| `Install-OpenCode.ps1` | OpenCode CLI from its update API (not on winget or GitHub releases) |

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
