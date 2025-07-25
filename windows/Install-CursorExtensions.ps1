#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Installs Cursor extensions

.DESCRIPTION
    This script installs a predefined list of Cursor extensions for development.
    It checks if Cursor is available before attempting to install extensions.

.NOTES
    Requirements:
    - Cursor must be installed and accessible via PATH
    - Internet connection for extension downloads
#>

param(
    [Parameter(HelpMessage="Custom list of extensions to install")]
    [string[]]$Extensions = @(),
    
    [Parameter(HelpMessage="Skip default extensions and only install custom ones")]
    [switch]$CustomOnly,
    
    [Parameter(HelpMessage="Force reinstall of extensions")]
    [switch]$Force
)

Write-Host "=== Cursor Extensions Installation ===" -ForegroundColor Cyan

# Check if Cursor is available
if (-not (Get-Command cursor -ErrorAction SilentlyContinue)) {
    Write-Warning "Cursor (cursor command) not found in PATH. Please ensure Cursor is installed and added to PATH."
    return @{
        status = "error"
        message = "Cursor not found in PATH"
    }
}

# Load default extensions from extensions.json file
$defaultExtensions = @()
$extensionsJsonPath = Join-Path (Split-Path $PSScriptRoot -Parent) "vscode\extensions.json"

if (Test-Path $extensionsJsonPath) {
    try {
        Write-Host "Loading extensions from: $extensionsJsonPath" -ForegroundColor Gray
        $extensionsJson = Get-Content $extensionsJsonPath -Raw | ConvertFrom-Json
        $defaultExtensions = $extensionsJson.extensions
        Write-Host "Loaded $($defaultExtensions.Count) extensions from extensions.json" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to load extensions.json: $_"
        Write-Host "Using fallback extension list..." -ForegroundColor Yellow
        # Fallback list in case JSON parsing fails
        $defaultExtensions = @(
            "eamodio.gitlens",
            "vscodevim.vim",
            "ms-vscode.powershell"
        )
    }
} else {
    Write-Warning "Extensions.json not found at: $extensionsJsonPath"
    Write-Host "Using fallback extension list..." -ForegroundColor Yellow
    # Fallback list in case file doesn't exist
    $defaultExtensions = @(
        "eamodio.gitlens",
        "vscodevim.vim", 
        "ms-vscode.powershell"
    )
}

# Determine which extensions to install
$extensionsToInstall = @()
if (-not $CustomOnly) {
    $extensionsToInstall += $defaultExtensions
}
if ($Extensions.Count -gt 0) {
    $extensionsToInstall += $Extensions
}

if ($extensionsToInstall.Count -eq 0) {
    Write-Host "No extensions specified for installation." -ForegroundColor Yellow
    return @{
        status = "skipped"
        message = "No extensions specified"
    }
}

Write-Host "Installing Cursor extensions..." -ForegroundColor Yellow
Write-Host "Extensions to install: $($extensionsToInstall.Count)" -ForegroundColor Gray

$installedCount = 0
$failedExtensions = @()
$skippedExtensions = @()

foreach ($extension in $extensionsToInstall) {
    try {
        Write-Host "Installing: $extension" -ForegroundColor Gray
        
        # Check if extension is already installed (unless force is specified)
        if (-not $Force) {
            $installedExtensions = cursor --list-extensions 2>$null
            if ($installedExtensions -contains $extension) {
                Write-Host "  Already installed: $extension" -ForegroundColor Green
                $skippedExtensions += $extension
                continue
            }
        }
        
        # Install the extension
        $installResult = cursor --install-extension $extension --force 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Successfully installed: $extension" -ForegroundColor Green
            $installedCount++
        } else {
            Write-Warning "  Failed to install: $extension - $installResult"
            $failedExtensions += $extension
        }
    } catch {
        Write-Warning "  Error installing $extension`: $_"
        $failedExtensions += $extension
    }
}

# Summary
Write-Host ""
Write-Host "Cursor Extensions Installation Summary:" -ForegroundColor Cyan
Write-Host "  Total extensions processed: $($extensionsToInstall.Count)" -ForegroundColor White
Write-Host "  Successfully installed: $installedCount" -ForegroundColor Green
Write-Host "  Already installed (skipped): $($skippedExtensions.Count)" -ForegroundColor Yellow
Write-Host "  Failed installations: $($failedExtensions.Count)" -ForegroundColor Red

if ($failedExtensions.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed extensions:" -ForegroundColor Red
    $failedExtensions | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

$status = if ($failedExtensions.Count -eq 0) { "success" } elseif ($installedCount -gt 0) { "partial" } else { "failed" }

return @{
    status = $status
    message = "Installed $installedCount extensions, $($failedExtensions.Count) failed"
    installed_count = $installedCount
    failed_count = $failedExtensions.Count
    skipped_count = $skippedExtensions.Count
    failed_extensions = $failedExtensions
} 
