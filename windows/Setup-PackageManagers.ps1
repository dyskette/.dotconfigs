#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Sets up winget package manager

.DESCRIPTION
    Ensures winget is installed and updated to the latest version.

.NOTES
    Requirements:
    - Windows 10 version 2004+ (Build 19041+) or Windows 11
    - Administrator privileges
    - Internet connection
#>

param(
    [Parameter(HelpMessage="Force reinstall of winget")]
    [switch]$Force
)

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

Write-Host "=== Winget Setup ===" -ForegroundColor Cyan

function Get-MajorMinorVersion {
    param([string]$version)
    $clean = $version -replace '[^\d\.]', ''
    $parts = $clean -split '\.'
    return @([int]$parts[0], [int]$parts[1])
}

function Update-EnvironmentPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Download latest release information
$tempFile = "$env:TEMP\winget_latest.json"
$shouldInstall = $false

try {
    Invoke-WebRequest -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -OutFile $tempFile -UseBasicParsing
    $latestJson = Get-Content $tempFile | ConvertFrom-Json
    $latestVersion = $latestJson.tag_name
    Write-Host "Latest winget version: $latestVersion" -ForegroundColor Gray

    $latestParsed = Get-MajorMinorVersion $latestVersion

    if (-not (Get-Command winget -ErrorAction SilentlyContinue) -or $Force) {
        Write-Host "Winget not found or force reinstall requested. Will install." -ForegroundColor Yellow
        $shouldInstall = $true
    } else {
        $installedVersion = winget --version
        Write-Host "Installed winget version: $installedVersion" -ForegroundColor Gray
        $installedParsed = Get-MajorMinorVersion $installedVersion

        if ($latestParsed[0] -gt $installedParsed[0] -or ($latestParsed[0] -eq $installedParsed[0] -and $latestParsed[1] -gt $installedParsed[1])) {
            Write-Host "New version available. Will update." -ForegroundColor Yellow
            $shouldInstall = $true
        } else {
            Write-Host "Winget is up to date." -ForegroundColor Green
        }
    }

    if ($shouldInstall) {
        $wingetUrl = $latestJson.assets | Where-Object { $_.browser_download_url -like '*.msixbundle' } | Select-Object -ExpandProperty browser_download_url
        if (-not $wingetUrl) {
            throw "Failed to find .msixbundle in release assets."
        }

        $msixPath = "$env:TEMP\Setup.msix"
        Write-Host "Downloading winget from: $wingetUrl" -ForegroundColor Gray
        Invoke-WebRequest -Uri $wingetUrl -OutFile $msixPath -UseBasicParsing

        Write-Host "Installing winget..." -ForegroundColor Yellow
        Add-AppxPackage -Path $msixPath
        Write-Host "Winget installed successfully." -ForegroundColor Green

        Update-EnvironmentPath
        Remove-Item -Force $msixPath -ErrorAction SilentlyContinue
    }

    Remove-Item -Force $tempFile -ErrorAction SilentlyContinue

    # Verify
    $finalVersion = winget --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Winget ready: $finalVersion" -ForegroundColor Green
        return @{
            status = "success"
            message = "Winget is ready ($finalVersion)"
            version = $finalVersion
        }
    } else {
        throw "Winget verification failed after installation."
    }

} catch {
    Remove-Item -Force $tempFile -ErrorAction SilentlyContinue
    Write-Error "Failed to setup winget: $_"
    return @{
        status = "error"
        message = "Winget setup failed: $_"
    }
}
