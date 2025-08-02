# Configure WezTerm terminal emulator
try {
    Write-Host "Configuring WezTerm..." -ForegroundColor Yellow
    $changesApplied = @()
    $errors = @()

    # Define source and destination paths
    $sourceConfigDir = Join-Path $PSScriptRoot ".." "wezterm"
    $destConfigDir = Join-Path $env:USERPROFILE ".config" "wezterm"

    # Create destination directory if it doesn't exist
    if (-not (Test-Path $destConfigDir)) {
        New-Item -Path $destConfigDir -ItemType Directory -Force | Out-Null
        $changesApplied += "Created WezTerm config directory"
    }

    # Create symbolic links for WezTerm configuration files
    $configFiles = @(
        "wezterm.lua",
        "everforest.lua",
        "gruvbox.lua", 
        "kanagawa-dragon.lua",
        "kanagawa-lotus.lua",
        "kanagawa-wave.lua",
        "rose-pine-dawn.lua"
    )

    foreach ($file in $configFiles) {
        $sourcePath = Join-Path $sourceConfigDir $file
        $destPath = Join-Path $destConfigDir $file

        if (Test-Path $sourcePath) {
            try {
                # Remove existing file or link if it exists
                if (Test-Path $destPath) {
                    Remove-Item -Path $destPath -Force
                }

                # Create symbolic link
                New-Item -ItemType SymbolicLink -Path $destPath -Target $sourcePath -Force | Out-Null
                $changesApplied += "Created symbolic link for $file"
            } catch {
                $errors += "Failed to create symbolic link for $file`: $($_.Exception.Message)"
            }
        } else {
            $errors += "Source file not found: $file"
        }
    }

    # Return results
    $result = @{
        status = if ($errors.Count -eq 0) { "success" } else { "partial" }
        message = "WezTerm configuration completed"
        changes_applied = $changesApplied
        errors = $errors
    }

    Write-Host "WezTerm configuration completed!" -ForegroundColor Green
    if ($changesApplied.Count -gt 0) {
        Write-Host "Changes applied:"
        $changesApplied | ForEach-Object { Write-Host "  - $_" }
    }

    if ($errors.Count -gt 0) {
        Write-Warning "Some errors occurred:"
        $errors | ForEach-Object { Write-Warning "  - $_" }
    }

    Write-Host "WezTerm is now configured with tmux integration and theme support." -ForegroundColor Green
    Write-Host "WezTerm will automatically start tmux inside WSL when launched." -ForegroundColor Cyan
    Write-Host "Configuration files are linked to the dotfiles repository for easy updates." -ForegroundColor Cyan

    return $result

} catch {
    Write-Error "Error configuring WezTerm: $($_.Exception.Message)"
    return @{
        status = "error"
        message = "Error configuring WezTerm: $($_.Exception.Message)"
        changes_applied = @()
        errors = @($_.Exception.Message)
    }
}
