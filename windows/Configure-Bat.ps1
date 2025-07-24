param(
    [string]$DotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\bat",
    [string]$BatConfigPath = "$env:APPDATA\bat"
)

# Update PATH environment variable
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "Configuring bat..." -ForegroundColor Green

if (Test-Path -Path $BatConfigPath) {
    Remove-Item -Path $BatConfigPath -Recurse -Force
    Write-Host "Existing directory $BatConfigPath removed." -ForegroundColor Yellow
}

if (-not (Test-Path -Path $DotfilesPath)) {
    Write-Error "Dotfiles path $DotfilesPath does not exist!"
    exit 1
}

New-Item -Path $BatConfigPath -Value $DotfilesPath -ItemType Junction
Write-Host "Junction created from $DotfilesPath to $BatConfigPath" -ForegroundColor Green

# Build bat cache for themes
try {
    & bat cache --build
    Write-Host "Bat cache built successfully." -ForegroundColor Green
} catch {
    Write-Warning "Failed to build bat cache: $_"
}

Write-Host "Bat configuration completed!" -ForegroundColor Green 