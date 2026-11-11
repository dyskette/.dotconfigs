# Windows Development Environment Setup

Automated Windows development environment configuration using **winget** for all package installation and PowerShell scripts for dotfile linking and system configuration.

## Quick Start

On a fresh Windows install, paste this into PowerShell as your normal user (no
git, winget, PowerShell 7, Administrator or execution policy change needed):

```powershell
irm https://raw.githubusercontent.com/dyskette/.dotconfigs/master/windows/Bootstrap.ps1 | iex
```

This downloads the repo to `~/.dotconfigs`, installs PowerShell 7 if it is
missing (winget, or the MSI from GitHub verified against its SHA256), runs the
full setup in PowerShell 7, and converts the directory into a git clone once
git is installed. Running it again is safe: an existing copy or clone is reused
(a clone is not pulled), and an unrelated `~/.dotconfigs` folder is refused.

If the repo is already cloned:

```powershell
# Run from PowerShell 7 as your normal user. Steps that need Administrator
# run together in one elevated window (one UAC prompt).
.\Install-WindowsEnvironment.ps1

# Show the plan without running anything
.\Install-WindowsEnvironment.ps1 -WhatIf

# Opt in / skip / pick steps by name or tag (see steps.psd1)
.\Install-WindowsEnvironment.ps1 -InstallWSL
.\Install-WindowsEnvironment.ps1 -Skip packages,Font
.\Install-WindowsEnvironment.ps1 -Only Dotfiles
```

Every step is safe to re-run. After a failure, or a restart a step asked for,
run the same command again and finished steps are skipped.

Exit codes: `0` success, `1` at least one step failed (see the summary),
`3010` restart Windows and run the same command again.

Logs: `~/.local/state/dotconfigs/logs/<timestamp>.log`, plus a
`<timestamp>-elevated.log` for the elevated part. The last 10 are kept.

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

Steps, their order, whether they need Administrator and their tags are
declared in `steps.psd1`.

| Parameter | Description |
|-----------|-------------|
| `-Skip <names/tags>` | Leave out steps by name or tag (`packages`, `config`, `wsl`) |
| `-Only <names/tags>` | Run only these steps (includes opt-in ones) |
| `-InstallWSL` | Include the opt-in WSL steps (tag `wsl`) |
| `-WhatIf` | Print the plan and exit |
| `-LogDirectory <path>` | Where transcripts go |

The earlier switches still work and map onto `-Skip`:

| Switch | Same as |
|--------|---------|
| `-SkipPackages` | `-Skip packages` |
| `-SkipGitHubPackages` | `-Skip GitHubReleases` |
| `-SkipOpenCode` | `-Skip OpenCode` |
| `-SkipConfiguration` | `-Skip Dotfiles` |
| `-SkipFont` | `-Skip Font` |
| `-SkipWindowsSettings` | `-Skip WindowsSettings` |
| `-SkipExtensions` | `-Skip Extensions` |
| `-SkipNodeSetup` | `-Skip NodeLTS` |

## Script Files

| File | Description |
|------|-------------|
| `Bootstrap.ps1` | One-liner entry point for fresh installs |
| `Install-WindowsEnvironment.ps1` | Main orchestrator |
| `steps.psd1` | Step table: order, Administrator flag, tags, parameters |
| `lib/Common.psm1` | Shared helpers (results, PATH, downloads, links, winget) |
| `lib/StepRunner.psm1` | Loads, selects and runs steps; elevation and summary |
| `lib/Invoke-ElevatedSteps.ps1` | Internal: runs the Administrator steps in the elevated window |
| `tests/` | Pester tests and `Invoke-Checks.ps1` (lint + tests, also run in CI) |
| `packages.jsonc` | Winget package manifest |
| `Install-WingetPackages.ps1` | `winget import` of `packages.jsonc`, with retries |
| `Install-VisualStudio.ps1` | Installs Visual Studio or adds the components in `vs/vsconfig.jsonc` |
| `language-tools.jsonc` | uv, cargo and go tools to install |
| `Install-LanguageTools.ps1` | Installs `language-tools.jsonc` (sets up LLVM/MSVC headers for cargo) |
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
