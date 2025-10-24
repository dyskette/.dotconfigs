param(
    [string]$DotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\bash",
    [string]$BashProfilePath = "$env:USERPROFILE"
)

Write-Host "Configuring bash..." -ForegroundColor Green

if (-not (Test-Path -Path $DotfilesPath)) {
    Write-Error "Dotfiles path $DotfilesPath does not exist!"
    exit 1
}

if (Test-Path -Path "$BashProfilePath\.bashrc") {
    Remove-Item -Path "$BashProfilePath\.bashrc" -Force
    Write-Host "Existing file $BashProfilePath\.bashrc removed." -ForegroundColor Yellow
}

if (Test-Path -Path "$BashProfilePath\.bashrc.d") {
    Remove-Item -Path "$BashProfilePath\.bashrc.d" -Recurse -Force
    Write-Host "Existing directory $BashProfilePath\.bashrc.d removed." -ForegroundColor Yellow
}

New-Item -Path "$BashProfilePath\.bashrc" -Target "$DotfilesPath\bashrc" -ItemType SymbolicLink
Write-Host "Symbolic link created from $DotfilesPath\bashrc to $BashProfilePath\.bashrc" -ForegroundColor Green

New-Item -Path "$BashProfilePath\.bashrc.d" -Value "$DotfilesPath\bashrc.d" -ItemType Junction
Write-Host "Junction created from $DotfilesPath\bashrc.d to $BashProfilePath\.bashrc.d" -ForegroundColor Green

Write-Host "Bash configuration completed!" -ForegroundColor Green
