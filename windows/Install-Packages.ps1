# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

# Setup package managers if not already done
function Initialize-PackageManagers {
    Write-Host "Setting up package managers..." -ForegroundColor Yellow
    $setupScript = Join-Path $PSScriptRoot "Setup-PackageManagers.ps1"
    
    if (-not (Test-Path $setupScript)) {
        Write-Error "CRITICAL: Package managers setup script not found at: $setupScript"
        exit 1
    }
    
    try {
        $setupResult = & $setupScript
        if ($setupResult.status -ne "success") {
            Write-Error "CRITICAL: Package managers setup failed: $($setupResult.message)"
            exit 1
        }
        
        $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
        $chocoAvailable = Get-Command choco -ErrorAction SilentlyContinue
        
        if (-not $wingetAvailable) {
            Write-Error "CRITICAL: winget is not available after setup."
            exit 1
        }
        
        if (-not $chocoAvailable) {
            Write-Error "CRITICAL: chocolatey is not available after setup."
            exit 1
        }
        
        Write-Host "Package managers setup completed successfully!" -ForegroundColor Green
        
    } catch {
        Write-Error "CRITICAL: Failed to run package managers setup script: $_"
        exit 1
    }
}

$packageMappings = @{
    mingw = @{
        name = "mingw"
        manager = "chocolatey"
    }
    deno = @{
        name = "DenoLand.Deno"
        manager = "winget"
    }
    make = @{
        name = "ezwinports.make"
        manager = "winget"
    }
    wget = @{
        name = "JernejSimoncic.Wget"
        manager = "winget"
    }
    jq = @{
        name = "jqlang.jq"
        manager = "winget"
    }
    yq = @{
        name = "MikeFarah.yq"
        manager = "winget"
    }
    fzf = @{
        name = "junegunn.fzf"
        manager = "winget"
    }
    fd = @{
        name = "sharkdp.fd"
        manager = "winget"
    }
    eza = @{
        name = "eza-community.eza"
        manager = "winget"
    }
    ripgrep = @{
        name = "BurntSushi.ripgrep.MSVC"
        manager = "winget"
    }
    bat = @{
        name = "sharkdp.bat"
        manager = "winget"
    }
    ffmpeg = @{
        name = "Gyan.FFmpeg"
        manager = "winget"
    }
    starship = @{
        name = "Starship.Starship"
        manager = "winget"
    }
    less = @{
        name = "jftuga.less"
        manager = "winget"
    }
    "powershell-core" = @{
        name = "Microsoft.PowerShell"
        manager = "winget"
    }
    fnm = @{
        name = "Schniz.fnm"
        manager = "winget"
    }
    python312 = @{
        name = "Python.Python.3.12"
        manager = "winget"
    }
    neovim = @{
        name = "Neovim.Neovim"
        manager = "winget"
    }
    "microsoft-windows-terminal" = @{
        name = "Microsoft.WindowsTerminal"
        manager = "winget"
    }
    vscode = @{
        name = "Microsoft.VisualStudioCode"
        manager = "winget"
    }
    obsidian = @{
        name = "Obsidian.Obsidian"
        manager = "winget"
    }
    firefox = @{
        name = "Mozilla.Firefox"
        manager = "winget"
    }
    keepassxc = @{
        name = "KeePassXCTeam.KeePassXC"
        manager = "winget"
    }
    dropbox = @{
        name = "Dropbox.Dropbox"
        manager = "winget"
    }
    yazi = @{
        name = "sxyazi.yazi"
        manager = "winget"
    }
    wezterm = @{
        name = "wez.wezterm"
        manager = "winget"
    }
}

function Test-WingetPackageInstalled {
    param(
        [string]$PackageId
    )
    
    try {
        $installedPackages = winget list --id $PackageId --exact 2>$null
        # If winget list returns successfully and contains the package ID, it's installed
        if ($LASTEXITCODE -eq 0 -and $installedPackages -match [regex]::Escape($PackageId)) {
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

function Test-ChocolateyPackageInstalled {
    param(
        [string]$PackageName
    )
    
    try {
        $installedPackages = choco list --local-only $PackageName --exact 2>$null
        # If choco list returns successfully and contains the package name, it's installed
        if ($LASTEXITCODE -eq 0 -and $installedPackages -match $PackageName) {
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

function Install-Packages {
    param(
        [string[]]$PackageNames
    )
    
    if ($PackageNames.Count -eq 0) {
        Write-Host "No packages specified for installation." -ForegroundColor Yellow
        return
    }
    
    # Initialize package managers
    Initialize-PackageManagers
    
    Write-Host ""
    Write-Host "Package Installation Summary:" -ForegroundColor Cyan
    Write-Host "   Total packages: $($PackageNames.Count)" -ForegroundColor Gray
    
    # Group packages by manager
    $wingetPackages = @()
    $chocoPackages = @()
    $unknownPackages = @()
    
    foreach ($packageName in $PackageNames) {
        if ($packageMappings.ContainsKey($packageName)) {
            $package = $packageMappings[$packageName]
            if ($package.manager -eq "winget") {
                $wingetPackages += $packageName
            } elseif ($package.manager -eq "chocolatey") {
                $chocoPackages += $packageName
            }
        } else {
            $unknownPackages += $packageName
        }
    }
    
    Write-Host "   Winget packages: $($wingetPackages.Count)" -ForegroundColor Gray
    Write-Host "   Chocolatey packages: $($chocoPackages.Count)" -ForegroundColor Gray
    if ($unknownPackages.Count -gt 0) {
        Write-Host "   Unknown packages: $($unknownPackages.Count)" -ForegroundColor Red
    }
    Write-Host ""
    
    $successCount = 0
    $failedCount = 0
    $skippedCount = 0
    $currentPackage = 0
    
    # Install winget packages
    if ($wingetPackages.Count -gt 0) {
        Write-Host "Installing Winget Packages:" -ForegroundColor Cyan
        foreach ($packageName in $wingetPackages) {
            $currentPackage++
            $package = $packageMappings[$packageName]
            $realName = $package.name
            
            Write-Host "[$currentPackage/$($PackageNames.Count)] Checking $packageName via winget..." -ForegroundColor Yellow
            
            # Check if package is already installed
            if (Test-WingetPackageInstalled -PackageId $realName) {
                Write-Host "    $packageName is already installed (skipping)" -ForegroundColor Cyan
                $skippedCount++
                continue
            }
            
            Write-Host "    Installing $packageName..." -ForegroundColor Yellow
            try {
                $result = winget install --exact --id $realName --silent --accept-source-agreements --accept-package-agreements 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    $packageName installed successfully" -ForegroundColor Green
                    $successCount++
                } elseif ($LASTEXITCODE -eq -1978335189) {
                    # Package already installed (fallback in case our check missed it)
                    Write-Host "    $packageName was already installed" -ForegroundColor Cyan
                    $skippedCount++
                } else {
                    Write-Host "    $packageName failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
                    $failedCount++
                }
            } catch {
                Write-Host "    $packageName error: $_" -ForegroundColor Red
                $failedCount++
            }
        }
        Write-Host ""
    }
    
    # Install chocolatey packages
    if ($chocoPackages.Count -gt 0) {
        Write-Host "Installing Chocolatey Packages:" -ForegroundColor Cyan
        foreach ($packageName in $chocoPackages) {
            $currentPackage++
            $package = $packageMappings[$packageName]
            $realName = $package.name
            
            Write-Host "[$currentPackage/$($PackageNames.Count)] Checking $packageName via chocolatey..." -ForegroundColor Yellow
            
            # Check if package is already installed
            if (Test-ChocolateyPackageInstalled -PackageName $realName) {
                Write-Host "    $packageName is already installed (skipping)" -ForegroundColor Cyan
                $skippedCount++
                continue
            }
            
            Write-Host "    Installing $packageName..." -ForegroundColor Yellow
            try {
                $result = choco install $realName -y 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    $packageName installed successfully" -ForegroundColor Green
                    $successCount++
                } else {
                    # Check if the error indicates the package is already installed
                    if ($result -match "already installed" -or $result -match "already exists") {
                        Write-Host "    $packageName was already installed" -ForegroundColor Cyan
                        $skippedCount++
                    } else {
                        Write-Host "    $packageName failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
                        $failedCount++
                    }
                }
            } catch {
                Write-Host "    $packageName error: $_" -ForegroundColor Red
                $failedCount++
            }
        }
        Write-Host ""
    }
    
    # Report unknown packages
    if ($unknownPackages.Count -gt 0) {
        Write-Host "Unknown Packages:" -ForegroundColor Red
        foreach ($packageName in $unknownPackages) {
            Write-Host "    $packageName not found in mappings" -ForegroundColor Red
            $failedCount++
        }
        Write-Host ""
    }
    
    # Final Summary
    Write-Host "Installation Complete!" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Total packages processed: $($PackageNames.Count)" -ForegroundColor White
    Write-Host "Newly installed: $successCount" -ForegroundColor Green
    Write-Host "Already installed (skipped): $skippedCount" -ForegroundColor Cyan
    Write-Host "Failed installations: $failedCount" -ForegroundColor Red
    Write-Host ""
    Write-Host "Package Manager Breakdown:" -ForegroundColor Gray
    Write-Host "   Winget: $($wingetPackages.Count) packages" -ForegroundColor Gray
    Write-Host "   Chocolatey: $($chocoPackages.Count) packages" -ForegroundColor Gray
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host ""
}

# This script provides the Install-Packages function for the main Windows environment setup
# It handles package installation via winget and chocolatey with enhanced logging and error handling