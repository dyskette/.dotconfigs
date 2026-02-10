#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Automated Windows development environment setup

.DESCRIPTION
    Orchestrates the full installation and configuration of a Windows development
    environment: package installation via winget, dotfile linking, font installation,
    editor extensions, and system settings.

.NOTES
    Requirements:
    - Windows 10 version 2004+ (Build 19041+) or Windows 11
    - Administrator privileges
    - Internet connection
#>

param(
    [Parameter(HelpMessage="Skip WSL installation")]
    [switch]$SkipWSL,

    [Parameter(HelpMessage="Skip package installation")]
    [switch]$SkipPackages,

    [Parameter(HelpMessage="Skip dotfile configuration")]
    [switch]$SkipConfiguration,

    [Parameter(HelpMessage="Skip editor extension installation")]
    [switch]$SkipExtensions,

    [Parameter(HelpMessage="Skip JetBrains Mono Nerd Font installation")]
    [switch]$SkipFont,

    [Parameter(HelpMessage="Skip Node.js LTS setup via fnm")]
    [switch]$SkipNodeSetup,

    [Parameter(HelpMessage="Skip Windows registry settings")]
    [switch]$SkipWindowsSettings
)

# ── Admin elevation ─────────────────────────────────────────────────────────

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Administrator privileges required. Attempting to elevate..." -ForegroundColor Yellow

    $argString = ""
    if ($PSBoundParameters.Count -gt 0) {
        $argString = ($PSBoundParameters.GetEnumerator() | ForEach-Object {
            if ($_.Value -eq $true) { "-$($_.Key)" }
            elseif ($_.Value -ne $false) { "-$($_.Key) '$($_.Value)'" }
        }) -join " "
    }

    try {
        $processArgs = @{
            FilePath     = "PowerShell"
            ArgumentList = @("-ExecutionPolicy", "Bypass", "-NoExit", "-File", "`"$($MyInvocation.MyCommand.Path)`"") + ($argString -split " " | Where-Object { $_ })
            Verb         = "RunAs"
            Wait         = $true
        }
        Start-Process @processArgs
        Write-Host "Script execution completed in elevated session." -ForegroundColor Green
        exit 0
    } catch {
        Write-Error "Failed to elevate to Administrator privileges: $_"
        Write-Warning "Please right-click PowerShell and select 'Run as Administrator', then run this script again."
        exit 1
    }
}

# ── Windows version check ──────────────────────────────────────────────────

$windowsVersion = [System.Environment]::OSVersion.Version
if ($windowsVersion.Build -lt 19041) {
    Write-Error "This script requires Windows 10 version 2004 (Build 19041) or higher."
    Write-Host "Current build: $($windowsVersion.Build)" -ForegroundColor Yellow
    exit 1
}
Write-Host "Windows version check passed: Build $($windowsVersion.Build)" -ForegroundColor Green

# ── Helper ──────────────────────────────────────────────────────────────────

function Invoke-Step {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{},
        [string]$Description
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path $scriptPath)) {
        Write-Warning "Script not found: $ScriptName"
        return @{ status = "error"; message = "Script not found" }
    }

    try {
        Write-Host "$Description..." -ForegroundColor Yellow
        $result = & $scriptPath @Parameters
        if ($result -and $result.status) {
            Write-Host "$Description completed: $($result.message)" -ForegroundColor Green
        } else {
            Write-Host "$Description completed." -ForegroundColor Green
        }
        return $result
    } catch {
        Write-Error "$Description failed: $_"
        return @{ status = "error"; message = $_.Exception.Message }
    }
}

function Update-SessionPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# ── 1. WSL ──────────────────────────────────────────────────────────────────

if (-not $SkipWSL) {
    $wslResult = Invoke-Step -ScriptName "Install-WSL.ps1" -Parameters @{ ForceRestart = $true } -Description "Setting up WSL with Ubuntu 24.04"
    if ($wslResult.restart_required) {
        Write-Host "WSL installation requires a restart. Please run this script again after restart." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "Skipping WSL installation." -ForegroundColor Yellow
}

# ── 2. Package installation ────────────────────────────────────────────────

if (-not $SkipPackages) {
    Write-Host ""
    Write-Host "=== Package Installation ===" -ForegroundColor Cyan

    # Bootstrap winget
    $pmResult = Invoke-Step -ScriptName "Setup-PackageManagers.ps1" -Description "Setting up winget"
    if ($pmResult.status -ne "success") {
        Write-Error "CRITICAL: Winget setup failed. Cannot proceed."
        exit 1
    }

    Update-SessionPath

    # Install packages from manifest
    $packagesJson = Join-Path $PSScriptRoot "packages.jsonc"
    if (Test-Path $packagesJson) {
        Write-Host "Installing packages via winget import..." -ForegroundColor Yellow
        winget import -i $packagesJson --accept-package-agreements --accept-source-agreements --ignore-unavailable
        Write-Host "Winget import completed." -ForegroundColor Green
    } else {
        Write-Warning "packages.jsonc not found at: $packagesJson"
    }

    # Install Visual Studio 2022 Enterprise with workloads from vsconfig
    $vsconfig = Join-Path (Split-Path $PSScriptRoot -Parent) "vs\vsconfig.jsonc"
    if (Test-Path $vsconfig) {
        Write-Host "Installing Visual Studio 2022 Enterprise..." -ForegroundColor Yellow
        winget install --exact --id Microsoft.VisualStudio.2022.Enterprise --silent --accept-package-agreements --accept-source-agreements --override "--wait --passive --norestart --config `"$vsconfig`""
        Write-Host "Visual Studio installation completed." -ForegroundColor Green
    } else {
        Write-Warning "vsconfig.jsonc not found at: $vsconfig"
    }

    Update-SessionPath

    # Install tools via uv/cargo/go
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Write-Host "Installing uv-based tools..." -ForegroundColor Yellow
        uv tool install poetry
        Write-Host "uv-based tools installed." -ForegroundColor Green
    } else {
        Write-Warning "uv not found in PATH. Skipping uv-based tool installation."
    }

    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        Write-Host "Installing Cargo-based tools..." -ForegroundColor Yellow

        # bindgen needs libclang.dll and clang needs MSVC/Windows SDK headers.
        # LLVM doesn't add itself to PATH, and clang targeting MSVC needs the
        # INCLUDE env var so it can find stdio.h etc. from the VC toolchain.
        $llvmBin = "C:\Program Files\LLVM\bin"
        if (Test-Path $llvmBin) {
            $env:LIBCLANG_PATH = $llvmBin
            $env:Path = "$llvmBin;$env:Path"
        }

        # Set INCLUDE for clang to find MSVC and Windows SDK headers
        if (-not $env:INCLUDE) {
            $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
            if (Test-Path $vswhere) {
                $vsPath = & $vswhere -latest -property installationPath
                $msvcDir = Get-ChildItem "$vsPath\VC\Tools\MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1
                $sdkVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots" -Name KitsRoot10 -ErrorAction SilentlyContinue).KitsRoot10
                if ($sdkVersion) {
                    $sdkInc = Get-ChildItem "${sdkVersion}Include" -Directory | Sort-Object Name -Descending | Select-Object -First 1
                }
                $includePaths = @()
                if ($msvcDir) { $includePaths += "$($msvcDir.FullName)\include" }
                if ($sdkInc) {
                    $includePaths += "$($sdkInc.FullName)\ucrt"
                    $includePaths += "$($sdkInc.FullName)\shared"
                    $includePaths += "$($sdkInc.FullName)\um"
                }
                if ($includePaths.Count -gt 0) {
                    $env:INCLUDE = $includePaths -join ";"
                }
            }
        }

        cargo install --locked tree-sitter-cli
        Write-Host "Cargo-based tools installed." -ForegroundColor Green
    } else {
        Write-Warning "Cargo not found in PATH. Skipping Cargo-based tool installation."
    }

    if (Get-Command go -ErrorAction SilentlyContinue) {
        Write-Host "Installing Go-based tools..." -ForegroundColor Yellow
        go install github.com/mhersson/mpls@latest
        Write-Host "Go-based tools installed." -ForegroundColor Green
    } else {
        Write-Warning "Go not found in PATH. Skipping Go-based tool installation."
    }
} else {
    Write-Host "Skipping package installation." -ForegroundColor Yellow
}

# ── 3. Dotfile configuration ───────────────────────────────────────────────

if (-not $SkipConfiguration) {
    Write-Host ""
    Write-Host "=== Dotfile Configuration ===" -ForegroundColor Cyan
    Invoke-Step -ScriptName "Configure-Dotfiles.ps1" -Description "Configuring dotfiles"
} else {
    Write-Host "Skipping dotfile configuration." -ForegroundColor Yellow
}

# ── 4. Font installation ───────────────────────────────────────────────────

if (-not $SkipFont) {
    Write-Host ""
    Invoke-Step -ScriptName "Install-JetBrainsFont.ps1" -Description "Installing JetBrains Mono Nerd Font"
} else {
    Write-Host "Skipping font installation." -ForegroundColor Yellow
}

# ── 5. Windows settings ────────────────────────────────────────────────────

if (-not $SkipWindowsSettings) {
    Write-Host ""
    Invoke-Step -ScriptName "Configure-WindowsSettings.ps1" -Description "Configuring Windows settings"
} else {
    Write-Host "Skipping Windows settings." -ForegroundColor Yellow
}

# ── 6. Editor extensions ───────────────────────────────────────────────────

if (-not $SkipExtensions) {
    Write-Host ""
    Invoke-Step -ScriptName "Install-Extensions.ps1" -Description "Installing editor extensions"
} else {
    Write-Host "Skipping editor extensions." -ForegroundColor Yellow
}

# ── 7. Node.js setup ───────────────────────────────────────────────────────

if (-not $SkipNodeSetup) {
    Write-Host ""
    Invoke-Step -ScriptName "Setup-NodeLTS.ps1" -Description "Setting up Node.js LTS via fnm"
} else {
    Write-Host "Skipping Node.js setup." -ForegroundColor Yellow
}

# ── Done ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== INSTALLATION COMPLETE ===" -ForegroundColor Green
Write-Host "Your Windows development environment has been configured." -ForegroundColor White
Write-Host "You may need to restart your shell to use newly installed tools." -ForegroundColor Yellow
