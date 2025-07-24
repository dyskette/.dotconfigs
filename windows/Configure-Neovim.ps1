param(
    [string]$DotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\nvim",
    [string]$NvimConfigPath = "$env:LOCALAPPDATA\nvim"
)

Write-Host "Configuring Neovim..." -ForegroundColor Green

if (Test-Path -Path $NvimConfigPath) {
    Remove-Item -Path $NvimConfigPath -Recurse -Force
    Write-Host "Existing directory $NvimConfigPath removed." -ForegroundColor Yellow
}

if (-not (Test-Path -Path $DotfilesPath)) {
    Write-Error "Dotfiles path $DotfilesPath does not exist!"
    exit 1
}

New-Item -Path $NvimConfigPath -Value $DotfilesPath -ItemType Junction
Write-Host "Junction created from $DotfilesPath to $NvimConfigPath" -ForegroundColor Green

Write-Host "Neovim configuration completed!" -ForegroundColor Green 