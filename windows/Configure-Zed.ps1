param(
    [string]$DotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\zed",
    [string]$ZedConfigPath = "$env:APPDATA\Zed"
)

Write-Host "Configuring Zed..." -ForegroundColor Green

$settingsSource = Join-Path $DotfilesPath "settings.json"
$settingsTarget = "$ZedConfigPath\settings.json"

$keymapSource = Join-Path $DotfilesPath "keymap.json"
$keymapTarget = "$ZedConfigPath\keymap.json"

if (-not (Test-Path -Path $DotfilesPath)) {
    Write-Error "Dotfiles path $DotfilesPath does not exist!"
    exit 1
}

if (-not (Test-Path -Path $settingsSource)) {
    Write-Error "Settings file $settingsSource does not exist!"
    exit 1
}

if (-not (Test-Path -Path $keymapSource)) {
    Write-Error "Keymap file $keymapSource does not exist!"
    exit 1
}

if (-not (Test-Path -Path $ZedConfigPath)) {
    New-Item -Path $ZedConfigPath -ItemType Directory -Force | Out-Null
    Write-Host "Created directory $ZedConfigPath" -ForegroundColor Yellow
}

# Remove existing symlinks/files if they exist
if (Test-Path -Path $settingsTarget) {
    Remove-Item -Path $settingsTarget -Force
    Write-Host "Existing settings file removed." -ForegroundColor Yellow
}

if (Test-Path -Path $keymapTarget) {
    Remove-Item -Path $keymapTarget -Force
    Write-Host "Existing keymap file removed." -ForegroundColor Yellow
}

New-Item -Path $settingsTarget -Target $settingsSource -ItemType SymbolicLink | Out-Null
New-Item -Path $keymapTarget -Target $keymapSource -ItemType SymbolicLink | Out-Null

Write-Host "Symbolic links created from $DotfilesPath to $ZedConfigPath" -ForegroundColor Green

Write-Host "Zed configuration completed!" -ForegroundColor Green
