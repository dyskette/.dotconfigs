#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Automated Windows development environment setup using Boxstarter

.DESCRIPTION
    This script uses Boxstarter and Chocolatey to install and configure Windows applications
    and development tools. It also sets up WSL with Ubuntu 24.04 for future use.
    
    Boxstarter provides a more reliable and simpler approach than WSL+Ansible for 
    Windows environment setup, with built-in reboot resilience.

.NOTES
    Requirements:
    - Windows 10 version 2004+ (Build 19041+) or Windows 11
    - Administrator privileges
    - Internet connection
#>

param(
    [Parameter(HelpMessage="Install only VS Code application")]
    [switch]$VSCode,
    
    [Parameter(HelpMessage="Install only VS Code extensions")]
    [switch]$VSCodeExtensions,
    
    [Parameter(HelpMessage="Install only JetBrains Mono Nerd Font")]
    [switch]$JetBrainsFont,
    
    [Parameter(HelpMessage="Install only MinGW compiler")]
    [switch]$MinGW,
    
    [Parameter(HelpMessage="Install only Deno runtime")]
    [switch]$Deno,
    
    [Parameter(HelpMessage="Install command-line tools (make, wget, jq, fzf, etc.)")]
    [switch]$CliTools,
    
    [Parameter(HelpMessage="Install only PowerShell Core")]
    [switch]$PowerShell,
    
    [Parameter(HelpMessage="Install only fnm (Fast Node Manager)")]
    [switch]$Fnm,
    
    [Parameter(HelpMessage="Install only Python 3.12")]
    [switch]$Python,
    
    [Parameter(HelpMessage="Install only Neovim")]
    [switch]$Neovim,
    
    [Parameter(HelpMessage="Install only Windows Terminal")]
    [switch]$WindowsTerminal,
    
    [Parameter(HelpMessage="Install productivity apps (Obsidian, Firefox, KeePassXC, Dropbox)")]
    [switch]$ProductivityApps,
    
    [Parameter(HelpMessage="Install only Yazi file manager")]
    [switch]$Yazi,
    
    [Parameter(HelpMessage="Install only WezTerm terminal")]
    [switch]$WezTerm,
    
    [Parameter(HelpMessage="Configure Windows settings (Explorer, Virtual Desktops, etc.)")]
    [switch]$WindowsConfig,
    
    [Parameter(HelpMessage="Configure all applications (bat, PowerShell, Starship, Neovim, VS Code, Windows Terminal)")]
    [switch]$Configuration,
    
    [Parameter(HelpMessage="Configure bat")]
    [switch]$BatConfig,
    
    [Parameter(HelpMessage="Configure PowerShell")]
    [switch]$PowerShellConfig,
    
    [Parameter(HelpMessage="Configure bash")]
    [switch]$BashConfig,
    
    [Parameter(HelpMessage="Configure Starship")]
    [switch]$StarshipConfig,
    
    [Parameter(HelpMessage="Configure Neovim")]
    [switch]$NeovimConfig,
    
    [Parameter(HelpMessage="Configure VS Code")]
    [switch]$VSCodeConfig,
    
    [Parameter(HelpMessage="Configure Windows Terminal")]
    [switch]$WindowsTerminalConfig,
    
    [Parameter(HelpMessage="Configure WezTerm")]
    [switch]$WezTermConfig,
    
    [Parameter(HelpMessage="Skip WSL installation")]
    [switch]$SkipWSL,
    
    [Parameter(HelpMessage="Run all tasks (default behavior)")]
    [switch]$All
)

# Check if running as Administrator and auto-elevate if needed
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Administrator privileges required. Attempting to elevate..." -ForegroundColor Yellow
    
    # Build the argument string for re-launching with the same parameters
    $argString = ""
    if ($PSBoundParameters.Count -gt 0) {
        $argString = ($PSBoundParameters.GetEnumerator() | ForEach-Object { 
            if ($_.Value -eq $true) { "-$($_.Key)" } 
            elseif ($_.Value -ne $false) { "-$($_.Key) '$($_.Value)'" }
        }) -join " "
    }
    
    try {
        # Re-launch the script with Administrator privileges
        $processArgs = @{
            FilePath = "PowerShell"
            ArgumentList = @("-ExecutionPolicy", "Bypass", "-File", "`"$($MyInvocation.MyCommand.Path)`"") + ($argString -split " " | Where-Object { $_ })
            Verb = "RunAs"
            Wait = $true
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

# Check Windows version compatibility
$windowsVersion = [System.Environment]::OSVersion.Version
$requiredBuild = 19041

if ($windowsVersion.Build -lt $requiredBuild) {
    Write-Error "This script requires Windows 10 version 2004 (Build 19041) or higher, or Windows 11."
    Write-Host "Current Windows version: $($windowsVersion.Major).$($windowsVersion.Minor) (Build $($windowsVersion.Build))" -ForegroundColor Yellow
    Write-Host "Please update Windows before running this script." -ForegroundColor Yellow
    exit 1
}

Write-Host "Windows version check passed: Build $($windowsVersion.Build)" -ForegroundColor Green

# Package installation will be handled by dedicated scripts using winget and chocolatey
Write-Host "Package installation will be handled by dedicated scripts..." -ForegroundColor Green

# Install WSL with Ubuntu 24.04 (for future use)
if (-not $SkipWSL) {
    Write-Host "Setting up WSL with Ubuntu 24.04..." -ForegroundColor Yellow
    try {
        $wslScriptPath = Join-Path $PSScriptRoot "Install-WSL.ps1"
        if (Test-Path $wslScriptPath) {
            $wslResult = & $wslScriptPath
            if ($wslResult.restart_required) {
                Write-Host "WSL installation requires a restart. Please run this script again after restart." -ForegroundColor Yellow
                exit 0
            }
            Write-Host "WSL setup completed: $($wslResult.message)" -ForegroundColor Green
        } else {
            Write-Warning "WSL installation script not found at: $wslScriptPath"
            Write-Host "Skipping WSL installation. You can install it manually later." -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Failed to run WSL installation script: $_"
        Write-Host "You can install WSL manually later using: wsl --install -d Ubuntu-24.04" -ForegroundColor Yellow
    }
} else {
    Write-Host "Skipping WSL installation (use -SkipWSL parameter)." -ForegroundColor Yellow
}

# Determine which components to install/configure
# Force boolean conversion to prevent array issues
$hasSpecificParams = $VSCode -or $VSCodeExtensions -or $JetBrainsFont -or $MinGW -or $Deno -or $CliTools -or $PowerShell -or $Fnm -or $Python -or $Neovim -or $WindowsTerminal -or $ProductivityApps -or $Yazi -or $WezTerm -or $WindowsConfig -or $Configuration -or $BatConfig -or $PowerShellConfig -or $BashConfig -or $StarshipConfig -or $NeovimConfig -or $VSCodeConfig -or $WindowsTerminalConfig -or $WezTermConfig
$runAll = [bool]($All -or (-not $hasSpecificParams))

# Helper function to run scripts with error handling
function Invoke-ModularScript {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{},
        [string]$Description = "Running script"
    )
    
    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (Test-Path $scriptPath) {
        try {
            Write-Host "$Description..." -ForegroundColor Yellow
            $result = & $scriptPath @Parameters
            
            # Check if the script exited with an error (LASTEXITCODE will be set)
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
                Write-Error "$Description failed with exit code: $LASTEXITCODE"
                return @{ status = "error"; message = "Script exited with code $LASTEXITCODE" }
            }
            
            # If we got a result object with status, use it
            if ($result -and $result.status) {
                Write-Host "$Description completed: $($result.message)" -ForegroundColor Green
                return $result
            } elseif ($result -eq $null) {
                # Script didn't return anything but didn't exit with error - this is suspicious
                Write-Warning "$Description completed but returned no result object"
                return @{ status = "error"; message = "Script completed but returned no result" }
            } else {
                Write-Host "$Description completed successfully." -ForegroundColor Green
                return @{ status = "success"; message = "Completed successfully" }
            }
        } catch {
            Write-Error "$Description failed: $_"
            return @{ status = "error"; message = $_.Exception.Message }
        }
    } else {
        Write-Warning "Script not found: $scriptPath"
        return @{ status = "error"; message = "Script not found: $ScriptName" }
    }
}

# Install packages using modular script
Write-Host "Installing packages..." -ForegroundColor Cyan
# Build package list for the new Install-Packages function
$packagesToInstall = @()

if ([bool]($runAll -or $MinGW)) { $packagesToInstall += "mingw" }
if ([bool]($runAll -or $Deno)) { $packagesToInstall += "deno" }
if ([bool]($runAll -or $CliTools)) { 
    $packagesToInstall += @("make", "wget", "jq", "yq", "fzf", "fd", "eza", "ripgrep", "bat", "ffmpeg", "starship", "less")
}
if ([bool]($runAll -or $PowerShell)) { $packagesToInstall += "powershell-core" }
if ([bool]($runAll -or $Fnm)) { $packagesToInstall += "fnm" }
if ([bool]($runAll -or $Python)) { $packagesToInstall += "python312" }
if ([bool]($runAll -or $Neovim)) { $packagesToInstall += "neovim" }
if ([bool]($runAll -or $WindowsTerminal)) { $packagesToInstall += "microsoft-windows-terminal" }
if ([bool]($runAll -or $VSCode)) { $packagesToInstall += "vscode" }
if ([bool]($runAll -or $ProductivityApps)) { 
    $packagesToInstall += @("obsidian", "firefox", "keepassxc", "dropbox")
}
if ([bool]($runAll -or $Yazi)) { $packagesToInstall += "yazi" }
if ([bool]($runAll -or $WezTerm)) { $packagesToInstall += "wezterm" }

# Call the Install-Packages script and function
$scriptPath = Join-Path $PSScriptRoot "Install-Packages.ps1"
if (Test-Path $scriptPath) {
    try {
        Write-Host "Installing packages via winget and chocolatey..." -ForegroundColor Yellow
        
        if ($packagesToInstall.Count -gt 0) {
            Write-Host "Installing $($packagesToInstall.Count) packages: $($packagesToInstall -join ', ')" -ForegroundColor Cyan
            
            # Source the script to load the function and mappings
            . $scriptPath
            
            # Call the Install-Packages function
            Install-Packages -PackageNames $packagesToInstall
            
            $packageResult = @{ status = "success"; message = "Package installation completed" }
        } else {
            Write-Host "No packages selected for installation." -ForegroundColor Yellow
            $packageResult = @{ status = "skipped"; message = "No packages specified" }
        }
    } catch {
        Write-Error "Installing packages via winget and chocolatey failed: $($_.Exception.Message)"
        $packageResult = @{ status = "error"; message = $_.Exception.Message }
    }
} else {
    Write-Warning "Script not found: Install-Packages.ps1"
    $packageResult = @{ status = "error"; message = "Script not found: Install-Packages.ps1" }
}

# Check if package installation succeeded
if ($packageResult.status -eq "error") {
    Write-Error "CRITICAL: Package installation failed: $($packageResult.message)"
    Write-Error "Cannot proceed without successful package installation. Please fix the issues and try again."
    exit 1
}

# Run post-installation configurations
Write-Host "Running post-installation configurations..." -ForegroundColor Cyan

if ($runAll -or $JetBrainsFont) {
    Invoke-ModularScript -ScriptName "Install-JetBrainsFont.ps1" -Description "Installing JetBrains Mono Nerd Font"
}

if ($runAll -or $WindowsConfig) {
    Invoke-ModularScript -ScriptName "Configure-WindowsSettings.ps1" -Description "Configuring Windows settings"
}

if ($runAll -or $PowerShellConfig -or $Configuration) {
    Invoke-ModularScript -ScriptName "Configure-PowerShell.ps1" -Description "Configuring PowerShell"
}

if ($runAll -or $BashConfig -or $Configuration) {
    Invoke-ModularScript -ScriptName "Configure-Bash.ps1" -Description "Configuring bash"
}

if ($runAll -or $BatConfig -or $Configuration) {
    Invoke-ModularScript -ScriptName "Configure-Bat.ps1" -Description "Configuring bat"
}

if ($runAll -or $StarshipConfig -or $Configuration) {
    Invoke-ModularScript -ScriptName "Configure-Starship.ps1" -Description "Configuring Starship"
}

if ($runAll -or $NeovimConfig -or $Configuration) {
    Invoke-ModularScript -ScriptName "Configure-Neovim.ps1" -Description "Configuring Neovim"
}

if ($runAll -or $VSCodeConfig -or $Configuration) {
    Invoke-ModularScript -ScriptName "Configure-VSCode.ps1" -Description "Configuring VS Code"
}

if ($runAll -or $WindowsTerminalConfig -or $Configuration) {
    Invoke-ModularScript -ScriptName "Configure-WindowsTerminal.ps1" -Description "Configuring Windows Terminal"
}

if ($runAll -or $WezTermConfig -or $Configuration) {
    Invoke-ModularScript -ScriptName "Configure-WezTerm.ps1" -Description "Configuring WezTerm"
}

if ($runAll -or $VSCodeExtensions) {
    Invoke-ModularScript -ScriptName "Install-VSCodeExtensions.ps1" -Description "Installing VS Code extensions"
}

if ($runAll -or $Fnm) {
    Invoke-ModularScript -ScriptName "Setup-NodeLTS.ps1" -Description "Setting up Node.js LTS via fnm"
}

Write-Host ""
Write-Host "=== INSTALLATION COMPLETE ===" -ForegroundColor Green
Write-Host "Your Windows development environment has been configured using Boxstarter!" -ForegroundColor White
Write-Host "WSL with Ubuntu 24.04 is available for future use." -ForegroundColor White
Write-Host ""
Write-Host "You may need to restart your shell to use newly installed tools." -ForegroundColor Yellow
Write-Host "Some applications may have been installed and are ready to use." -ForegroundColor White 
