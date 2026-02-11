#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Data-driven dotfiles configuration via symlinks and junctions

.DESCRIPTION
    Creates symbolic links and directory junctions from dotfiles to their
    expected application config locations. Handles post-link hooks and
    environment variable setup.

.NOTES
    Requirements:
    - Administrator privileges (required for symlinks on Windows)
#>

param(
    [Parameter(HelpMessage="Only configure specific apps (e.g. 'nvim','vscode','bat')")]
    [string[]]$Filter = @()
)

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

$dotfilesRoot = Split-Path -Parent $PSScriptRoot

# Refresh PATH so newly-installed tools are available
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# ── Link table ──────────────────────────────────────────────────────────────
# Each entry: App (for filtering), Source (relative to dotfiles root),
# Target (absolute path), Type (Junction or SymbolicLink), and optional
# PostHook / EnvVar.

$links = @(
    @{
        App    = "nvim"
        Source = "nvim"
        Target = "$env:LOCALAPPDATA\nvim"
        Type   = "Junction"
    }
    @{
        App    = "powershell"
        Source = "powershell"
        Target = "$env:USERPROFILE\Documents\PowerShell"
        Type   = "Junction"
    }
    @{
        App    = "bat"
        Source = "bat"
        Target = "$env:APPDATA\bat"
        Type   = "Junction"
        PostHook = { bat cache --build 2>&1 | Out-Null }
    }
    @{
        App    = "starship"
        Source = "starship"
        Target = "$env:USERPROFILE\.config\starship"
        Type   = "Junction"
        EnvVar = @{ Name = "STARSHIP_CONFIG"; Value = "$env:USERPROFILE\.config\starship\config.toml"; Scope = "User" }
    }
    @{
        App    = "bash"
        Source = "bash\bashrc"
        Target = "$env:USERPROFILE\.bashrc"
        Type   = "SymbolicLink"
    }
    @{
        App    = "bash"
        Source = "bash\bashrc.d"
        Target = "$env:USERPROFILE\.bashrc.d"
        Type   = "Junction"
    }
    @{
        App    = "vscode"
        Source = "vscode\settings.json"
        Target = "$env:APPDATA\Code\User\settings.json"
        Type   = "SymbolicLink"
    }
    @{
        App    = "vscode"
        Source = "vscode\keybindings.json"
        Target = "$env:APPDATA\Code\User\keybindings.json"
        Type   = "SymbolicLink"
    }
    @{
        App    = "windows-terminal"
        Source = "windows_terminal\settings.json"
        Target = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        Type   = "SymbolicLink"
    }
    @{
        App    = "wezterm"
        Source = "wezterm\*.lua"
        Target = "$env:USERPROFILE\.config\wezterm"
        Type   = "Directory"
    }
    @{
        App    = "yazi"
        Source = "yazi"
        Target = "$env:APPDATA\yazi\config"
        Type   = "Junction"
    }
    @{
        App    = "zed"
        Source = "zed\settings.json"
        Target = "$env:APPDATA\Zed\settings.json"
        Type   = "HardLink"
    }
    @{
        App    = "zed"
        Source = "zed\keymap.json"
        Target = "$env:APPDATA\Zed\keymap.json"
        Type   = "HardLink"
    }
)

# ── LocalBin (special: creates dir + adds to PATH) ─────────────────────────

$localBinPath = "$env:USERPROFILE\.local\bin"

# ── Helper functions ────────────────────────────────────────────────────────

function New-Link {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Type
    )

    $parentDir = Split-Path $Target -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }

    if (Test-Path $Target) {
        Remove-Item -Path $Target -Force -Recurse
    }

    if ($Type -eq "Junction") {
        New-Item -Path $Target -Value $Source -ItemType Junction | Out-Null
    } elseif ($Type -eq "HardLink") {
        New-Item -Path $Target -Value $Source -ItemType HardLink | Out-Null
    } else {
        New-Item -Path $Target -Target $Source -ItemType SymbolicLink | Out-Null
    }
}

# ── Main ────────────────────────────────────────────────────────────────────

Write-Host "=== Dotfiles Configuration ===" -ForegroundColor Cyan

$successCount = 0
$failedCount = 0
$skippedCount = 0

# Process LocalBin
$shouldProcessLocalBin = ($Filter.Count -eq 0) -or ($Filter -contains "localbin")
if ($shouldProcessLocalBin) {
    try {
        Write-Host "Configuring local bin directory..." -ForegroundColor Yellow
        if (-not (Test-Path -Path $localBinPath)) {
            New-Item -Path $localBinPath -ItemType Directory -Force | Out-Null
            Write-Host "  Created $localBinPath" -ForegroundColor Green
        }

        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not ($userPath -split ";" | Where-Object { $_ -eq $localBinPath })) {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$localBinPath", "User")
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            Write-Host "  Added $localBinPath to user PATH" -ForegroundColor Green
        } else {
            Write-Host "  $localBinPath already in PATH" -ForegroundColor Cyan
        }
        $successCount++
    } catch {
        Write-Warning "  Failed to configure local bin: $_"
        $failedCount++
    }
}

# Process link table
foreach ($link in $links) {
    # Apply filter
    if ($Filter.Count -gt 0 -and $Filter -notcontains $link.App) {
        $skippedCount++
        continue
    }

    $sourcePath = Join-Path $dotfilesRoot $link.Source

    try {
        # Handle Directory type (glob pattern — symlink each matching file)
        if ($link.Type -eq "Directory") {
            $sourceFiles = Get-ChildItem -Path $sourcePath -ErrorAction Stop
            if ($sourceFiles.Count -eq 0) {
                Write-Warning "  No files matched: $sourcePath"
                $failedCount++
                continue
            }

            $targetDir = $link.Target
            if (-not (Test-Path $targetDir)) {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }

            foreach ($file in $sourceFiles) {
                $fileTarget = Join-Path $targetDir $file.Name
                if (Test-Path $fileTarget) {
                    Remove-Item -Path $fileTarget -Force
                }
                New-Item -Path $fileTarget -Target $file.FullName -ItemType SymbolicLink | Out-Null
            }

            Write-Host "  [$($link.App)] Linked $($sourceFiles.Count) files -> $targetDir" -ForegroundColor Green
            $successCount++
        } else {
            # Junction or SymbolicLink
            if (-not (Test-Path $sourcePath)) {
                Write-Warning "  [$($link.App)] Source not found: $sourcePath"
                $failedCount++
                continue
            }

            New-Link -Source $sourcePath -Target $link.Target -Type $link.Type
            Write-Host "  [$($link.App)] $($link.Type): $($link.Source) -> $($link.Target)" -ForegroundColor Green
            $successCount++
        }

        # Run post-hook if defined
        if ($link.PostHook) {
            try {
                & $link.PostHook
                Write-Host "  [$($link.App)] Post-hook completed" -ForegroundColor Gray
            } catch {
                Write-Warning "  [$($link.App)] Post-hook failed: $_"
            }
        }

        # Set environment variable if defined
        if ($link.EnvVar) {
            [Environment]::SetEnvironmentVariable($link.EnvVar.Name, $link.EnvVar.Value, $link.EnvVar.Scope)
            Write-Host "  [$($link.App)] Set $($link.EnvVar.Name) = $($link.EnvVar.Value)" -ForegroundColor Gray
        }

    } catch {
        Write-Warning "  [$($link.App)] Failed: $_"
        $failedCount++
    }
}

# Summary
Write-Host ""
Write-Host "Dotfiles Configuration Summary:" -ForegroundColor Cyan
Write-Host "  Succeeded: $successCount" -ForegroundColor Green
Write-Host "  Failed: $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped (filtered): $skippedCount" -ForegroundColor Gray

$status = if ($failedCount -eq 0) { "success" } elseif ($successCount -gt 0) { "partial" } else { "error" }

return @{
    status = $status
    message = "Configured $successCount links, $failedCount failed"
    succeeded = $successCount
    failed = $failedCount
    skipped = $skippedCount
}
