param(
    [string]$DotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\windows_terminal",
    [string]$WindowsTerminalConfigPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
)

Write-Host "Configuring Windows Terminal..." -ForegroundColor Green

$settingsSource = Join-Path $DotfilesPath "settings.json"
$settingsTarget = "$WindowsTerminalConfigPath\settings.json"

if (-not (Test-Path -Path $DotfilesPath)) {
    Write-Error "Dotfiles path $DotfilesPath does not exist!"
    exit 1
}

if (-not (Test-Path -Path $settingsSource)) {
    Write-Error "Settings file $settingsSource does not exist!"
    exit 1
}

if (-not (Test-Path -Path $WindowsTerminalConfigPath)) {
    Write-Host "Creating Windows Terminal configuration directory..." -ForegroundColor Yellow
    New-Item -Path $WindowsTerminalConfigPath -ItemType Directory -Force | Out-Null
} else {
    if (Test-Path -Path $settingsTarget) {
        Write-Host "Existing file $settingsTarget removed." -ForegroundColor Yellow
        Remove-Item -Path $settingsTarget -Force
    }
}

New-Item -Path $settingsTarget -Target $settingsSource -ItemType SymbolicLink | Out-Null
Write-Host "Symbolic link created from $settingsSource to $settingsTarget" -ForegroundColor Green

Write-Host "Windows Terminal configuration completed!" -ForegroundColor Green 