# Windows development environment setup

Installs and configures a Windows development machine from this repository:
packages through winget, tools without a winget package from their own
releases, dotfile links, a Nerd Font, editor extensions and a few Windows
settings. Every step is safe to re-run, and a re-run upgrades what is installed.

## Quick start

On a fresh machine, paste into PowerShell as your normal user (no git, winget,
PowerShell 7, Administrator or execution policy change needed):

```powershell
irm https://raw.githubusercontent.com/dyskette/.dotconfigs/master/windows/Bootstrap.ps1 | iex
```

It downloads the repository to `~/.dotconfigs`, installs PowerShell 7 if it is
missing, runs the full setup in PowerShell 7 and turns the folder into a git
clone once git is installed. Running it again reuses the existing copy (a
clone is not pulled); an unrelated `~/.dotconfigs` folder is refused.

With the repository already cloned, from **PowerShell 7 as your normal user**:

```powershell
cd ~/.dotconfigs
./windows/Install-WindowsEnvironment.ps1 -WhatIf            # show the plan, run nothing
./windows/Install-WindowsEnvironment.ps1                    # everything (one UAC prompt)
./windows/Install-WindowsEnvironment.ps1 -Only Dotfiles     # pick steps by name or tag
./windows/Install-WindowsEnvironment.ps1 -Skip packages,Font
./windows/Install-WindowsEnvironment.ps1 -InstallWSL        # include the opt-in WSL steps
```

The bootstrap one-liner runs whatever is on GitHub `master`; a local run uses
the working copy. Push before using the one-liner on another machine.

## Requirements

- Windows 10 2004 (build 19041) or later, or Windows 11
- An account that can approve a UAC prompt
- Internet access to GitHub, the winget source, Oracle, EnterpriseDB,
  opencode.ai and the Visual Studio Marketplace
- Optional: Developer Mode, so `~/.local/bin` holds links instead of copies

## How it works

`Install-WindowsEnvironment.ps1` runs the steps declared in `steps.psd1`, in
order. The design choices, and why:

- **Privileges**: it runs as you. Steps marked `Admin` run together in one
  elevated window, which checks it belongs to the same user. Everything else
  runs unelevated, so a bug in a user-level step never has admin rights.
- **Results**: each step reports `Success`, `Skipped` (nothing to do), `Partial`, `Failed`
  or `RestartRequired`. The summary lists every step.
- **Exit codes**: `0` success, `1` a step failed or partly failed, `3010`
  restart Windows and run the same command again. Nothing reboots on its own.
- **Upgrades**: a re-run updates every tool to its latest version, except
  Visual Studio and editor extensions, which update themselves.
- **Safety**: downloads are verified and swapped in atomically; existing config files are
  moved to `<name>.bak-<timestamp>`, never deleted.
- **Shell**: everything needs PowerShell 7, except `Bootstrap.ps1`, which stays
  Windows PowerShell 5.1-compatible and ASCII-only because a fresh machine has
  only 5.1; it just installs PowerShell 7 and hands over.
- **Bootstrap source**: it downloads `master` unpinned, with no hash check.
  Fine for a single-user repository; it means unpushed changes are not used.
- **No resume file**: every step is idempotent, so the same command continues
  after a failure or restart.
- **Logs**: `~/.local/state/dotconfigs/logs/<timestamp>.log`, plus
  `<timestamp>-elevated.log` for the elevated part. The last 10 are kept.

### Steps

| Step | Admin | Tags | Does |
|------|:-----:|------|------|
| `WslFeatures` | yes | wsl (opt-in) | Enables the WSL Windows features; may ask for a restart |
| `WslDistro` | yes | wsl (opt-in) | `wsl --update`, installs Ubuntu 24.04, merges `.wslconfig` / `.wslgconfig` |
| `PackageManagers` | yes | packages | Makes sure winget works and updates it (critical) |
| `WingetPackages` | yes | packages | `winget import` of `packages.jsonc` |
| `Psql` | yes | packages | PostgreSQL client tools only (no server) |
| `VisualStudio` | yes | packages | Installs Visual Studio or adds the components in `vs/vsconfig.jsonc` |
| `Dotfiles` | yes | config | Links from `links.jsonc`; creates `~/.local/bin` and puts it on PATH |
| `SqlPlus` | | packages | Oracle Instant Client + SQL*Plus |
| `LanguageTools` | | packages | uv and go tools from `language-tools.jsonc` |
| `GitHubReleases` | | packages | Tools from `github-packages.jsonc` |
| `OpenCode` | | packages | OpenCode CLI from its update API |
| `Font` | | config | JetBrains Mono NL Nerd Font, per user |
| `WindowsSettings` | | config | Explorer and Alt+Tab settings (HKCU) |
| `Extensions` | | config | VS Code (`vscode/extensions.json`) and Visual Studio (`vs/extensions.jsonc`) |
| `NodeLTS` | | packages | Latest Node.js LTS via fnm, as the default |

The earlier switches still work: `-SkipPackages` (= `-Skip packages`),
`-SkipGitHubPackages`, `-SkipOpenCode`, `-SkipConfiguration` (= `Dotfiles`),
`-SkipFont`, `-SkipWindowsSettings`, `-SkipExtensions`, `-SkipNodeSetup`.

## Configuration

The manifests are the source of truth for what gets installed and linked.

| File | Contents |
|------|----------|
| `steps.psd1` | Steps: order, Admin, Critical, opt-in, tags, parameters (Visual Studio edition and version range, PostgreSQL major version) |
| `packages.jsonc` | winget packages |
| `github-packages.jsonc` | Tools taken from GitHub releases; per entry an optional `version` pin and `require_checksum` |
| `language-tools.jsonc` | uv, cargo and go tools |
| `links.jsonc` | Dotfile links: `source` (repo-relative), `target` (`%VARS%` expanded), `type` (`Junction` for folders, `SymbolicLink` for files), optional `post` command |
| `../vs/vsconfig.jsonc` | Visual Studio components |
| `../vs/extensions.jsonc`, `../vscode/extensions.json` | Editor extensions |

Installs outside winget go to `~/.local/opt/<name>`, with their versions in
`~/.local/opt/versions.json` and their executables linked (or copied) into
`~/.local/bin`.

### Environment variables

| Variable | Used by | Purpose |
|----------|---------|---------|
| `GITHUB_TOKEN` | GitHub release lookups (winget update, font, `github-packages.jsonc`) | Optional. Raises the API limit from 60 to 5000 requests per hour. Set it for the session only, from a secret store rather than a persistent variable, e.g. `$env:GITHUB_TOKEN = gh auth token` or `Get-Secret` (SecretManagement). |
| `SYSTEM_COLOR_THEME` | psmux theme scripts | Set by the PowerShell profile from the Windows app theme. |

## Runbook

Start with the summary line of the failed step, then the logs. After fixing
the cause, run the same command again: finished steps report `Skipped`.

| Symptom | Cause and fix |
|---------|---------------|
| Admin steps all `Failed`: "Elevation was declined" | The UAC prompt was cancelled. Run again and accept it. |
| "Elevated as a different user" | UAC was approved with another account. Sign in as an administrator, or run from an elevated prompt as yourself. |
| Exit code `3010` | A step (WSL features) needs a restart. Restart, run the same command. |
| "GitHub API rate limit reached until ..." | Set `GITHUB_TOKEN` (see above) or wait until the time shown. |
| `PackageManagers` `Partial` | winget works but could not be updated; the run continued. Retry later. |
| winget exit `0x8A15000F` | Corrupt source index. Retried automatically after a reset; manually: `winget source reset --force`. |
| `WingetPackages` `Partial` | One or more packages failed. Logs: `%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir`. |
| `Psql` fails with `0x80072EE2` | Download timeout, often a VPN tunnelling CloudFront ranges. Disconnect the VPN and run again. |
| "Visual Studio is running; close it" | VSIXInstaller cannot modify a running instance. Close Visual Studio and run again. |
| "is a program from it still running?" | An upgrade could not replace an install in use (OpenCode, a release tool). The old install was kept; close the program and run again. |
| "symbolic links need Administrator or Developer Mode" | `Configure-Dotfiles.ps1` was run directly, unelevated. Run it through the orchestrator, or enable Developer Mode. |
| A config file was replaced by a link | The original is next to it as `<name>.bak-<timestamp>`. Remove the link and rename the backup to restore it. |
| A tool is still the old version in a terminal | PATH changes reach new processes only. Open a new terminal. |

There is no uninstall: remove packages with `winget uninstall`, folders under
`~/.local/opt`, and links by deleting them (only the link is removed).

## Development

### Checks

```powershell
Install-PSResource Pester, PSScriptAnalyzer -Scope CurrentUser -TrustRepository   # once
./windows/tests/Invoke-Checks.ps1           # lint + tests + coverage
./windows/tests/Invoke-Checks.ps1 -Lint
./windows/tests/Invoke-Checks.ps1 -Test
```

CI (`.github/workflows/powershell.yml`, `windows-latest`) runs the same checks
plus `Install-WindowsEnvironment.ps1 -WhatIf -InstallWSL` on every change to a
PowerShell file or manifest. Any lint finding or test failure fails the run;
coverage target is 75%.

`Documents\PowerShell` is a junction to `powershell/`, so CurrentUser module
installs land in the repository; `powershell/Modules/` is gitignored.

### Testing safely

Tests never install anything: installers, downloads, GitHub and winget are
mocked, registry writes go to `HKCU\Software\DotconfigsTests`, files to
Pester's `$TestDrive`. Keep it that way. Do not test the bootstrap against
GitHub `master` while changes are unpushed: it runs the old scripts, including
real installers.

### Conventions

Enforced by `tests/Repository.Tests.ps1` and PSScriptAnalyzer
(`PSScriptAnalyzerSettings.psd1` at the repository root):

- `#Requires -Version 7`, `[CmdletBinding()]`, `Set-StrictMode -Version Latest`,
  `$ErrorActionPreference = 'Stop'` (the bootstrap: 5.1-compatible, ASCII-only).
- Comment-based help on every script and function (PSScriptAnalyzer checks exported ones): what it does and why.
- External programs through `Invoke-Native` (pass flags with `-Arguments`;
  inline flags can bind to its own parameters) or `Invoke-Winget`.
- PATH only through `Add-PathEntry` / `Remove-PathEntry`.
- No `Remove-Item -Recurse` without a `# safe: <reason>` comment on the line;
  links through `Remove-LinkOnly` / `Set-Link`.
- Pass `-WhatIf:$WhatIfPreference` to module functions; preference variables
  do not flow from a script into a module.
- Locals and parameters need distinct names: `$bin` and `$Bin` are the same
  variable.

### Adding a step

1. Write `windows/<Verb-Noun>.ps1` from this template and return exactly one
   result:

   ```powershell
   #Requires -Version 7
   <#
   .SYNOPSIS
   What the step does.

   .DESCRIPTION
   Why it is done this way, and how it decides there is nothing to do.

   .OUTPUTS
   Dotconfigs.StepResult
   #>
   [CmdletBinding()]   # SupportsShouldProcess only if it also calls $PSCmdlet.ShouldProcess
   param()

   Set-StrictMode -Version Latest
   $ErrorActionPreference = 'Stop'

   Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

   if (<already done>) { return New-StepResult Skipped 'Already done.' }
   # ... do the work ...
   return New-StepResult Success 'Did the thing.' -Data @{ Version = $version }
   ```

2. Add an entry to `steps.psd1` (`Admin = $true` only if it really needs it,
   listed with the other admin steps).
3. Add tests in `windows/tests/` that mock every installer and assert the
   result for: nothing to do, install, upgrade, failure.

### Adding a package or link

- A tool on winget: add it to `packages.jsonc`. Prefer winget over the other
  manifests.
- A tool only on GitHub releases: add it to `github-packages.jsonc` with an
  `asset_pattern` that matches exactly one asset.
- A uv or go tool: add it to `language-tools.jsonc`.
- A config file or folder: add it to `links.jsonc`; a test checks the source
  exists.

## Files

| Path | Purpose |
|------|---------|
| `Bootstrap.ps1` | Fresh-machine entry point (Windows PowerShell 5.1) |
| `Install-WindowsEnvironment.ps1` | Orchestrator |
| `lib/Common.psm1` | Shared helpers: results, native calls, winget, downloads, checksums, PATH, links, atomic installs, version records |
| `lib/StepRunner.psm1` | Loads, selects, batches and runs steps; summary and exit code |
| `lib/Invoke-ElevatedSteps.ps1` | Runs the admin steps in the elevated window (internal) |
| `Setup-PackageManagers.ps1`, `Install-*.ps1`, `Configure-*.ps1`, `Setup-NodeLTS.ps1` | Steps (see the table above) |
| `tests/` | Pester tests, `Invoke-Checks.ps1` |
