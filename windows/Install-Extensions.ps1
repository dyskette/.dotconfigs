#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Installs extensions for VS Code and/or Cursor

.DESCRIPTION
    Loads extensions from vscode/extensions.json and installs them using
    the CLI for each specified editor. Skips editors not found in PATH.

.NOTES
    Requirements:
    - Target editor(s) must be installed and accessible via PATH
    - Internet connection for extension downloads
#>

param(
    [Parameter(HelpMessage="Which editor CLIs to install extensions for")]
    [ValidateSet("code")]
    [string[]]$Editors = @("code"),

    [Parameter(HelpMessage="Additional extensions to install")]
    [string[]]$Extensions = @(),

    [Parameter(HelpMessage="Skip default extensions and only install custom ones")]
    [switch]$CustomOnly,

    [Parameter(HelpMessage="Force reinstall of extensions")]
    [switch]$Force
)

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "=== Editor Extensions Installation ===" -ForegroundColor Cyan

# Load default extensions from extensions.json
$defaultExtensions = @()
$extensionsJsonPath = Join-Path (Split-Path $PSScriptRoot -Parent) "vscode\extensions.json"

if (Test-Path $extensionsJsonPath) {
    try {
        Write-Host "Loading extensions from: $extensionsJsonPath" -ForegroundColor Gray
        $extensionsJson = Get-Content $extensionsJsonPath -Raw | ConvertFrom-Json
        $defaultExtensions = $extensionsJson.extensions
        Write-Host "Loaded $($defaultExtensions.Count) extensions" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to load extensions.json: $_"
        $defaultExtensions = @("eamodio.gitlens", "vscodevim.vim", "ms-vscode.powershell")
    }
} else {
    Write-Warning "extensions.json not found at: $extensionsJsonPath"
    $defaultExtensions = @("eamodio.gitlens", "vscodevim.vim", "ms-vscode.powershell")
}

# Build extension list
$extensionsToInstall = @()
if (-not $CustomOnly) {
    $extensionsToInstall += $defaultExtensions
}
if ($Extensions.Count -gt 0) {
    $extensionsToInstall += $Extensions
}

if ($extensionsToInstall.Count -eq 0) {
    Write-Host "No extensions specified for installation." -ForegroundColor Yellow
    return @{ status = "skipped"; message = "No extensions specified" }
}

$allResults = @{}

foreach ($editor in $Editors) {
    $editorName = "VS Code"

    if (-not (Get-Command $editor -ErrorAction SilentlyContinue)) {
        Write-Warning "$editorName ($editor) not found in PATH. Skipping."
        $allResults[$editor] = @{ status = "skipped"; message = "Not found in PATH" }
        continue
    }

    Write-Host ""
    Write-Host "Installing $editorName extensions..." -ForegroundColor Yellow

    $installedCount = 0
    $failedExtensions = @()
    $skippedExtensions = @()

    # Get already-installed extensions once
    $installedExtensions = @()
    if (-not $Force) {
        $installedExtensions = & $editor --list-extensions 2>$null
    }

    foreach ($extension in $extensionsToInstall) {
        if (-not $Force -and $installedExtensions -contains $extension) {
            Write-Host "  Already installed: $extension" -ForegroundColor Cyan
            $skippedExtensions += $extension
            continue
        }

        try {
            $installResult = & $editor --install-extension $extension --force 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Installed: $extension" -ForegroundColor Green
                $installedCount++
            } else {
                Write-Warning "  Failed: $extension - $installResult"
                $failedExtensions += $extension
            }
        } catch {
            Write-Warning "  Error: $extension - $_"
            $failedExtensions += $extension
        }
    }

    Write-Host ""
    Write-Host "$editorName Summary:" -ForegroundColor Cyan
    Write-Host "  Installed: $installedCount" -ForegroundColor Green
    Write-Host "  Skipped: $($skippedExtensions.Count)" -ForegroundColor Cyan
    Write-Host "  Failed: $($failedExtensions.Count)" -ForegroundColor $(if ($failedExtensions.Count -gt 0) { "Red" } else { "Green" })

    if ($failedExtensions.Count -gt 0) {
        $failedExtensions | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    }

    $status = if ($failedExtensions.Count -eq 0) { "success" } elseif ($installedCount -gt 0) { "partial" } else { "failed" }
    $allResults[$editor] = @{
        status = $status
        installed_count = $installedCount
        failed_count = $failedExtensions.Count
        skipped_count = $skippedExtensions.Count
        failed_extensions = $failedExtensions
    }
}

# Overall status
$overallFailed = ($allResults.Values | Where-Object { $_.status -eq "failed" }).Count
$overallStatus = if ($overallFailed -eq $allResults.Count) { "failed" } elseif ($overallFailed -gt 0) { "partial" } else { "success" }

return @{
    status = $overallStatus
    message = "Extension installation completed"
    results = $allResults
}
