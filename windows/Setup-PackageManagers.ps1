#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Sets up winget and chocolatey package managers

.DESCRIPTION
    This script ensures both winget and chocolatey are installed and properly configured.
    Winget is updated to the latest version if needed, and chocolatey is installed via winget.
    Both package managers are added to PATH for immediate use.

.NOTES
    Requirements:
    - Windows 10 version 2004+ (Build 19041+) or Windows 11
    - Administrator privileges
    - Internet connection
#>

param(
    [Parameter(HelpMessage="Force reinstall of package managers")]
    [switch]$Force
)

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

Write-Host "=== Package Managers Setup ===" -ForegroundColor Cyan

function Get-MajorMinorVersion {
    param([string]$version)

    # Strip non-digit/dot characters, e.g., 'v1.11.400' -> '1.11.400'
    $clean = $version -replace '[^\d\.]', ''

    # Split version into parts
    $parts = $clean -split '\.'

    # Return array of integers: major, minor
    return @([int]$parts[0], [int]$parts[1])
}

function Update-EnvironmentPath {
    Write-Host "Updating environment PATH..." -ForegroundColor Yellow
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Install-Winget {
    Write-Host "Setting up winget..." -ForegroundColor Yellow
    
    $shouldInstallWinget = $false
    
    # Download latest release information
    $tempFile = "$env:TEMP\winget_latest.json"
    try {
        Invoke-WebRequest -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -OutFile $tempFile -UseBasicParsing
        
        # Parse release information
        $latestJson = (Get-Content $tempFile | ConvertFrom-Json)
        $latestVersion = $latestJson.tag_name # e.g., v1.11.400
        Write-Host "Latest winget version: $latestVersion" -ForegroundColor Gray
        
        $latestVersionParsed = Get-MajorMinorVersion $latestVersion
        
        if (-not (Get-Command winget -ErrorAction SilentlyContinue) -or $Force) {
            if ($Force) {
                Write-Host "Force reinstall requested." -ForegroundColor Yellow
            } else {
                Write-Host "Winget not found. Will install." -ForegroundColor Yellow
            }
            $shouldInstallWinget = $true
        } else {
            $installedVersion = (winget --version)  # e.g., v1.6.10121
            Write-Host "Currently installed winget version: $installedVersion" -ForegroundColor Gray
            
            $installedVersionParsed = Get-MajorMinorVersion $installedVersion
            
            if ($latestVersionParsed[0] -gt $installedVersionParsed[0] -or ($latestVersionParsed[0] -eq $installedVersionParsed[0] -and $latestVersionParsed[1] -gt $installedVersionParsed[1])) {
                Write-Host "New version available. Will update." -ForegroundColor Yellow
                $shouldInstallWinget = $true
            } else {
                Write-Host "Winget is up to date." -ForegroundColor Green
            }
        }
        
        if ($shouldInstallWinget) {
            $wingetUrl = $latestJson.assets | Where-Object { $_.browser_download_url -like '*.msixbundle' } | Select-Object -ExpandProperty browser_download_url
            
            if (-not $wingetUrl) {
                throw "Failed to find .msixbundle in release assets."
            }
            
            $msixPath = "$env:TEMP\Setup.msix"
            Write-Host "Downloading winget from: $wingetUrl" -ForegroundColor Gray
            Invoke-WebRequest -Uri $wingetUrl -OutFile $msixPath -UseBasicParsing
            
            # Install winget
            Write-Host "Installing winget..." -ForegroundColor Yellow
            Add-AppxPackage -Path $msixPath
            Write-Host "Winget installed successfully." -ForegroundColor Green
            
            # Update PATH environment variable
            Update-EnvironmentPath
            
            # Clean up
            Remove-Item -Force $msixPath -ErrorAction SilentlyContinue
        }
        
        # Clean up temp file
        Remove-Item -Force $tempFile -ErrorAction SilentlyContinue
        
        return @{
            status = "success"
            message = "Winget setup completed successfully"
            installed = $shouldInstallWinget
        }
        
    } catch {
        Write-Warning "Failed to setup winget: $_"
        Remove-Item -Force $tempFile -ErrorAction SilentlyContinue
        return @{
            status = "error"
            message = "Winget setup failed: $_"
        }
    }
}

function Install-Chocolatey {
    Write-Host "Setting up chocolatey..." -ForegroundColor Yellow
    
    # Check if chocolatey is already installed
    if ((Get-Command choco -ErrorAction SilentlyContinue) -and -not $Force) {
        Write-Host "Chocolatey is already installed." -ForegroundColor Green
        
        # Update environment variables for chocolatey
        Update-ChocolateyEnvironment
        
        return @{
            status = "success"
            message = "Chocolatey already installed"
            installed = $false
        }
    }
    
    try {
        if ($Force -and (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Host "Force reinstall requested for chocolatey." -ForegroundColor Yellow
        }
        
        # Try to install chocolatey via winget first
        Write-Host "Installing chocolatey via winget..." -ForegroundColor Yellow
        winget install --exact --id Chocolatey.Chocolatey --silent --accept-source-agreements --accept-package-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Chocolatey installed successfully via winget." -ForegroundColor Green
        } else {
            throw "Winget installation failed with exit code $LASTEXITCODE"
        }
        
        # Update environment variables for chocolatey
        Update-ChocolateyEnvironment
        
        return @{
            status = "success"
            message = "Chocolatey installed via winget"
            installed = $true
        }
        
    } catch {
        Write-Warning "Failed to install chocolatey via winget: $_"
        Write-Host "Falling back to direct chocolatey installation..." -ForegroundColor Yellow
        
        try {
            # Fallback to direct chocolatey installation
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            
            # Update environment variables for chocolatey
            Update-ChocolateyEnvironment
            
            return @{
                status = "success"
                message = "Chocolatey installed via direct method"
                installed = $true
            }
        } catch {
            Write-Warning "Failed to install chocolatey via direct method: $_"
            return @{
                status = "error"
                message = "Chocolatey installation failed: $_"
            }
        }
    }
}

function Update-ChocolateyEnvironment {
    Write-Host "Updating chocolatey environment variables..." -ForegroundColor Yellow
    
    $InstallDir = "C:\ProgramData\chocolatey"
    $env:ChocolateyInstall = [Environment]::GetEnvironmentVariable("ChocolateyInstall", "Machine")
    
    # Update PATH environment variable
    Update-EnvironmentPath
    
    if ($env:Path -notlike "*$InstallDir*") {
        $env:Path += ";$InstallDir"
        Write-Host "Added chocolatey to PATH." -ForegroundColor Green
    }
}

function Test-PackageManagers {
    Write-Host "Testing package managers..." -ForegroundColor Yellow
    
    $results = @{
        winget = @{ available = $false; version = $null }
        chocolatey = @{ available = $false; version = $null }
    }
    
    # Test winget
    try {
        $wingetVersion = winget --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $results.winget.available = $true
            $results.winget.version = $wingetVersion
            Write-Host "  [OK] Winget: $wingetVersion" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [ERROR] Winget: Not available" -ForegroundColor Red
    }
    
    # Test chocolatey
    try {
        $chocoVersion = choco --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $results.chocolatey.available = $true
            $results.chocolatey.version = $chocoVersion
            Write-Host "  [OK] Chocolatey: $chocoVersion" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [ERROR] Chocolatey: Not available" -ForegroundColor Red
    }
    
    return $results
}

# Main execution
Write-Host "Setting up package managers..." -ForegroundColor Cyan

# Install winget first
$wingetResult = Install-Winget
if ($wingetResult.status -ne "success") {
    Write-Error "Failed to setup winget: $($wingetResult.message)"
    exit 1
}

# Install chocolatey (preferably via winget)
$chocoResult = Install-Chocolatey
if ($chocoResult.status -ne "success") {
    Write-Error "Failed to setup chocolatey: $($chocoResult.message)"
    exit 1
}

# Test both package managers
$testResults = Test-PackageManagers

# Summary
Write-Host ""
Write-Host "Package Managers Setup Summary:" -ForegroundColor Cyan

# Check winget status (PowerShell 5.1 compatible)
if ($testResults.winget.available) {
    Write-Host "  Winget: [OK] Available ($($testResults.winget.version))" -ForegroundColor White
} else {
    Write-Host "  Winget: [ERROR] Not available" -ForegroundColor White
}

# Check chocolatey status (PowerShell 5.1 compatible)
if ($testResults.chocolatey.available) {
    Write-Host "  Chocolatey: [OK] Available ($($testResults.chocolatey.version))" -ForegroundColor White
} else {
    Write-Host "  Chocolatey: [ERROR] Not available" -ForegroundColor White
}

if ($testResults.winget.available -and $testResults.chocolatey.available) {
    Write-Host "Both package managers are ready!" -ForegroundColor Green
    return @{
        status = "success"
        message = "Both winget and chocolatey are ready"
        winget = $testResults.winget
        chocolatey = $testResults.chocolatey
    }
} else {
    Write-Error "CRITICAL: One or more package managers failed to install properly."
    Write-Error "Winget available: $($testResults.winget.available)"
    Write-Error "Chocolatey available: $($testResults.chocolatey.available)"
    Write-Error "Cannot proceed without both package managers working."
    exit 1
} 