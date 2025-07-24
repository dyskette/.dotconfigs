param(
    [string]$DotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\powershell",
    [string]$PowerShellProfilePath = "$env:USERPROFILE\Documents\PowerShell"
)

Write-Host "Configuring PowerShell..." -ForegroundColor Green

if (Test-Path -Path $PowerShellProfilePath) {
    Remove-Item -Path $PowerShellProfilePath -Recurse -Force
    Write-Host "Existing directory $PowerShellProfilePath removed." -ForegroundColor Yellow
}

if (-not (Test-Path -Path $DotfilesPath)) {
    Write-Error "Dotfiles path $DotfilesPath does not exist!"
    exit 1
}

New-Item -Path $PowerShellProfilePath -Value $DotfilesPath -ItemType Junction
Write-Host "Junction created from $DotfilesPath to $PowerShellProfilePath" -ForegroundColor Green

Write-Host "PowerShell configuration completed!" -ForegroundColor Green 