param(
    [string]$DotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\vscode",
    [string]$CursorUserPath = "$env:APPDATA\Cursor\User"
)

# Update PATH environment variable
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "Configuring Cursor..." -ForegroundColor Green

$settingsSource = Join-Path $DotfilesPath "settings.json"
$settingsTarget = "$CursorUserPath\settings.json"

$keybindingsSource = Join-Path $DotfilesPath "keybindings.json"
$keybindingsTarget = "$CursorUserPath\keybindings.json"

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

if (Test-Path -Path $CursorUserPath) {
    Remove-Item -Path $CursorUserPath -Force -Recurse
    Write-Host "Existing directory $CursorUserPath removed." -ForegroundColor Yellow
}

New-Item -Path $CursorUserPath -ItemType Directory -Force | Out-Null
New-Item -Path $settingsTarget -Target $settingsSource -ItemType SymbolicLink | Out-Null
New-Item -Path $keybindingsTarget -Target $keybindingsSource -ItemType SymbolicLink | Out-Null

Write-Host "Symbolic links created from $DotfilesPath to $CursorUserPath" -ForegroundColor Green

Write-Host "Cursor configuration completed!" -ForegroundColor Green 
