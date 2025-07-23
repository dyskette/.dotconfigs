# Setup fnm environment and install Node.js LTS
try {
    # Update PATH environment variable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Check if fnm is available
    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        Write-Warning "fnm not found in PATH. Please ensure fnm is installed and restart your shell."
        return @{
            status = "error"
            message = "fnm not found in PATH"
        }
    }

    Write-Host "Setting up fnm environment..."
    
    # Setup fnm environment
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression

    Write-Host "Installing Node.js LTS version..."
    
    # Install LTS version
    $installResult = fnm install --lts 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install Node.js LTS: $installResult"
        return @{
            status = "error"
            message = "Failed to install Node.js LTS: $installResult"
        }
    }

    Write-Host "Setting LTS as default version..."
    
    # Set LTS as default
    $defaultResult = fnm default lts/latest 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to set LTS as default: $defaultResult"
        return @{
            status = "error"
            message = "Failed to set LTS as default: $defaultResult"
        }
    }

    # Get installed version info
    $nodeVersion = node --version 2>&1
    $npmVersion = npm --version 2>&1

    Write-Host "Node.js LTS setup completed successfully!"
    Write-Host "Node.js version: $nodeVersion"
    Write-Host "npm version: $npmVersion"

    return @{
        status = "success"
        message = "Node.js LTS installed and set as default"
        node_version = $nodeVersion
        npm_version = $npmVersion
    }

} catch {
    Write-Error "Error setting up Node.js LTS: $($_.Exception.Message)"
    return @{
        status = "error"
        message = "Error setting up Node.js LTS: $($_.Exception.Message)"
    }
} 