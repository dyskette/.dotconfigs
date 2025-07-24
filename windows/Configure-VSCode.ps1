param(
    [string]$DotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\vscode",
    [string]$CodeUserPath = "$env:APPDATA\Code\User"
)

# Update PATH environment variable
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "Configuring VS Code..." -ForegroundColor Green

$settingsSource = Join-Path $DotfilesPath "settings.json"
$settingsTarget = "$CodeUserPath\settings.json"

$keybindingsSource = Join-Path $DotfilesPath "keybindings.json"
$keybindingsTarget = "$CodeUserPath\keybindings.json"

if (-not (Test-Path -Path $DotfilesPath)) {
    Write-Error "Dotfiles path $DotfilesPath does not exist!"
    exit 1
}

if (-not (Test-Path -Path $settingsSource)) {
    Write-Error "Settings file $settingsSource does not exist!"
    exit 1
}

if (-not (Test-Path -Path $keybindingsSource)) {
    Write-Error "Keybindings file $keybindingsSource does not exist!"
    exit 1
}

if (Test-Path -Path $CodeUserPath) {
    Remove-Item -Path $CodeUserPath -Force -Recurse
    Write-Host "Existing directory $CodeUserPath removed." -ForegroundColor Yellow
}

New-Item -Path $CodeUserPath -ItemType Directory -Force | Out-Null
New-Item -Path $settingsTarget -Target $settingsSource -ItemType SymbolicLink | Out-Null
New-Item -Path $keybindingsTarget -Target $keybindingsSource -ItemType SymbolicLink | Out-Null

Write-Host "Symbolic links created from $DotfilesPath to $CodeUserPath" -ForegroundColor Green

Write-Host "VS Code configuration completed!" -ForegroundColor Green 