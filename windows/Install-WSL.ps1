#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Installs and configures WSL with Ubuntu 24.04 LTS

.DESCRIPTION
    This script enables the required Windows features for WSL, handles restarts,
    and installs Ubuntu 24.04 LTS distribution. It's designed to be called from
    the main installation script but can also be run independently.

.NOTES
    Requirements:
    - Windows 10 version 2004+ (Build 19041+) or Windows 11
    - Administrator privileges
    - Internet connection
#>

param(
    [Parameter(HelpMessage="Skip WSL installation and only enable features")]
    [switch]$FeaturesOnly,
    
    [Parameter(HelpMessage="Force restart after enabling features")]
    [switch]$ForceRestart
)

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

Write-Host "=== WSL Installation Script ===" -ForegroundColor Cyan
Write-Host "Setting up Windows Subsystem for Linux with Ubuntu 24.04..." -ForegroundColor White

# Helper: Write .wslgconfig for HiDPI support
function Write-WSLgConfig {
    $wslgConfigFile = "$env:USERPROFILE\.wslgconfig"
    try {
        $wslgConfig = @"
[system-distro-env]
WESTON_RDP_DISABLE_FRACTIONAL_HI_DPI_SCALING=true
WESTON_RDP_FRACTIONAL_HI_DPI_SCALING=false
"@
        Set-Content -Path $wslgConfigFile -Value $wslgConfig -Force
        Write-Host "Created .wslgconfig with HiDPI scaling support" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to create .wslgconfig: $_"
    }
}

# Enable WSL features before installing distributions
Write-Host "Ensuring WSL features are enabled..." -ForegroundColor Yellow

$needsRestart = $false

# Check and enable Windows Subsystem for Linux feature
try {
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslFeature.State -ne "Enabled") {
        Write-Host "Enabling Windows Subsystem for Linux feature..." -ForegroundColor Yellow
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
        Write-Host "WSL feature enabled." -ForegroundColor Green
        $needsRestart = $true
    } else {
        Write-Host "Windows Subsystem for Linux feature is already enabled." -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not check or enable WSL feature: $_"
}

# Check and enable Virtual Machine Platform feature (required for WSL 2)
try {
    $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
    if ($vmFeature.State -ne "Enabled") {
        Write-Host "Enabling Virtual Machine Platform feature..." -ForegroundColor Yellow
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
        Write-Host "Virtual Machine Platform feature enabled." -ForegroundColor Green
        $needsRestart = $true
    } else {
        Write-Host "Virtual Machine Platform feature is already enabled." -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not check or enable Virtual Machine Platform feature: $_"
}

# If only enabling features, exit here
if ($FeaturesOnly) {
    if ($needsRestart) {
        Write-Host "WSL features have been enabled. A restart is required for changes to take effect." -ForegroundColor Yellow
        if ($ForceRestart) {
            Write-Host "Restarting computer..." -ForegroundColor Yellow
            Restart-Computer -Force
        }
        return @{ 
            status = "features_enabled"
            restart_required = $true 
        }
    } else {
        Write-Host "All WSL features are already enabled." -ForegroundColor Green
        return @{ 
            status = "features_ready"
            restart_required = $false 
        }
    }
}

# Check if restart is needed before proceeding with WSL installation
if ($needsRestart) {
    Write-Host ""
    Write-Host "=== RESTART REQUIRED ===" -ForegroundColor Cyan
    Write-Host "WSL features have been enabled but require a restart to take effect." -ForegroundColor White
    Write-Host ""
    Write-Host "Please:" -ForegroundColor Yellow
    Write-Host "1. Restart your computer" -ForegroundColor White
    Write-Host "2. Run this script again to continue with Ubuntu installation" -ForegroundColor White
    Write-Host ""
    
    if ($ForceRestart) {
        Write-Host "Auto-restarting in 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        Restart-Computer -Force
        exit 0
    } else {
        Write-Host "Press any key to restart now, or Ctrl+C to restart manually later..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Restart-Computer -Force
        exit 0
    }
}

# Install WSL with Ubuntu 24.04
Write-Host "Installing WSL with Ubuntu 24.04..." -ForegroundColor Yellow

# Check if Ubuntu 24.04 is already installed
$wslDistributions = wsl --list --quiet 2>$null
if ($wslDistributions.Split() -contains "Ubuntu-24.04") {
    Write-Host "Ubuntu 24.04 is already installed in WSL." -ForegroundColor Green
    
    # Set it as default if it's not
    try {
        $defaultDist = wsl --list --verbose 2>$null | Where-Object { $_ -match "\*" } | ForEach-Object { ($_ -split '\s+')[1] }
        if ($defaultDist -ne "Ubuntu-24.04") {
            Write-Host "Setting Ubuntu 24.04 as default WSL distribution..." -ForegroundColor Yellow
            wsl --set-default Ubuntu-24.04
            Write-Host "Ubuntu 24.04 set as default." -ForegroundColor Green
        }
    } catch {
        Write-Warning "Could not set Ubuntu 24.04 as default: $_"
    }
    
    Write-WSLgConfig

    return @{
        status = "already_installed"
        message = "Ubuntu 24.04 is already installed and configured"
    }
}

# Install Ubuntu 24.04
try {
    Write-Host "Downloading and installing Ubuntu 24.04..." -ForegroundColor Yellow
    wsl --install -d Ubuntu-24.04 --no-launch
    
    # Verify installation
    Start-Sleep -Seconds 3
    if ((wsl --list --quiet 2>&1) | Select-String "Ubuntu-24.04") {
        Write-Host "Ubuntu 24.04 installed successfully!" -ForegroundColor Green
        
        # Set as default distribution
        try {
            wsl --set-default Ubuntu-24.04
            Write-Host "Ubuntu 24.04 set as default WSL distribution." -ForegroundColor Green
        } catch {
            Write-Warning "Could not set Ubuntu 24.04 as default: $_"
        }
        
        Write-Host ""
        Write-Host "WSL Setup Complete!" -ForegroundColor Green
        Write-Host "Ubuntu 24.04 is ready for use (not launched automatically)." -ForegroundColor White
        Write-Host "To access Ubuntu: wsl or ubuntu2404.exe" -ForegroundColor Gray
        
        Write-WSLgConfig

        return @{
            status = "installed"
            message = "Ubuntu 24.04 installed and configured successfully"
        }
    } else {
        throw "Installation verification failed"
    }
    
} catch {
    Write-Warning "Failed to install Ubuntu 24.04 via WSL: $_"
    Write-Host ""
    Write-Host "Alternative installation methods:" -ForegroundColor Yellow
    Write-Host "1. Install from Microsoft Store: ms-windows-store://pdp/?ProductId=9NZ3KLHXDJP5" -ForegroundColor White
    Write-Host "2. Manual WSL setup: wsl --install" -ForegroundColor White
    
    return @{
        status = "failed"
        message = "Ubuntu 24.04 installation failed: $_"
        manual_install_required = $true
    }
} 