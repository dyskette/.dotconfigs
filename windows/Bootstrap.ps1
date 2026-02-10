#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Bootstrap script for setting up the dotfiles on a fresh Windows install

.DESCRIPTION
    Downloads the dotfiles repository from GitHub (no git required), extracts
    it to ~/.dotconfigs, and runs the main orchestrator. After packages are
    installed (including git), converts the directory into a proper git clone
    so future updates work via git pull.

    One-liner to run on a fresh machine (paste into PowerShell):

        Set-ExecutionPolicy Bypass -Scope Process -Force; iwr 'https://raw.githubusercontent.com/dyskette/.dotconfigs/master/windows/Bootstrap.ps1' -UseBasicParsing | iex

.NOTES
    Requirements:
    - Windows 10 version 2004+ (Build 19041+) or Windows 11
    - Internet connection
    - Will self-elevate to Administrator
#>

$ErrorActionPreference = "Stop"

# TLS 1.2 — PowerShell 5.1 defaults to old TLS, GitHub requires 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dotfilesDir = "$env:USERPROFILE\.dotconfigs"
$repoUrl = "https://github.com/dyskette/.dotconfigs"
$zipUrl = "$repoUrl/archive/refs/heads/master.zip"
$zipPath = "$env:TEMP\dotconfigs.zip"
$extractPath = "$env:TEMP\dotconfigs-extract"

Write-Host "=== Dotfiles Bootstrap ===" -ForegroundColor Cyan

# ── Download and extract ────────────────────────────────────────────────────

if (Test-Path $dotfilesDir) {
    Write-Host "Dotfiles directory already exists at $dotfilesDir" -ForegroundColor Yellow
    Write-Host "Skipping download and running orchestrator directly." -ForegroundColor Yellow
} else {
    Write-Host "Downloading dotfiles from GitHub..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

    Write-Host "Extracting..." -ForegroundColor Yellow
    if (Test-Path $extractPath) {
        Remove-Item -Path $extractPath -Recurse -Force
    }
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # GitHub zips to a subdirectory named <repo>-<branch>
    $extracted = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
    Move-Item -Path $extracted.FullName -Destination $dotfilesDir
    Write-Host "Dotfiles extracted to $dotfilesDir" -ForegroundColor Green

    # Cleanup
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Run orchestrator ────────────────────────────────────────────────────────

$orchestrator = Join-Path $dotfilesDir "windows\Install-WindowsEnvironment.ps1"
if (-not (Test-Path $orchestrator)) {
    Write-Error "Orchestrator not found at: $orchestrator"
    exit 1
}

Write-Host "Running environment setup..." -ForegroundColor Yellow
& $orchestrator

# ── Convert to git clone ───────────────────────────────────────────────────

# After the orchestrator finishes, git should be installed via winget.
# Convert the extracted zip into a proper git repo so git pull works.
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

if ((Get-Command git -ErrorAction SilentlyContinue) -and -not (Test-Path "$dotfilesDir\.git")) {
    Write-Host ""
    Write-Host "Converting to git repository..." -ForegroundColor Yellow
    Push-Location $dotfilesDir
    try {
        git init
        git remote add origin "https://github.com/dyskette/.dotconfigs.git"
        git fetch origin master
        git reset --mixed origin/master
        Write-Host "Git repository initialized. Use 'git pull' for future updates." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to initialize git repo: $_"
        Write-Host "You can manually clone later: git clone git@github.com:dyskette/.dotconfigs.git" -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
} elseif (Test-Path "$dotfilesDir\.git") {
    Write-Host "Already a git repository." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Bootstrap Complete ===" -ForegroundColor Green
