param(
    [string]$DotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\starship",
    [string]$StarshipConfigPath = "$env:USERPROFILE\.config"
)

Write-Host "Configuring Starship..." -ForegroundColor Green

$configSource = Join-Path $DotfilesPath "config.toml"
$configDir = "$StarshipConfigPath\starship"
$configTarget = "$configDir\config.toml"

if (-not (Test-Path -Path $DotfilesPath)) {
    Write-Error "Dotfiles path $DotfilesPath does not exist!"
    exit 1
}

if (-not (Test-Path -Path $configSource)) {
    Write-Error "Config file $configSource does not exist!"
    exit 1
}

# Create .config directory if it doesn't exist
if (-not (Test-Path -Path $StarshipConfigPath)) {
    New-Item -Path $StarshipConfigPath -ItemType Directory -Force | Out-Null
    Write-Host "Created .config directory at $StarshipConfigPath" -ForegroundColor Yellow
}

# Remove existing starship config directory and create junction
if (Test-Path -Path $configDir) {
    Remove-Item -Path $configDir -Recurse -Force
    Write-Host "Existing directory $configDir removed." -ForegroundColor Yellow
}

New-Item -Path $configDir -Value $DotfilesPath -ItemType Junction | Out-Null
Write-Host "Junction created from $DotfilesPath to $configDir" -ForegroundColor Green

# Set environment variable for Starship config
[Environment]::SetEnvironmentVariable("STARSHIP_CONFIG", "$configDir\config.toml", "User")
Write-Host "STARSHIP_CONFIG environment variable set to $configDir\config.toml" -ForegroundColor Green

Write-Host "Starship configuration completed!" -ForegroundColor Green 