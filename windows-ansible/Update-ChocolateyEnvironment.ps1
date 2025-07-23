$InstallDir = "C:\ProgramData\chocolatey"
$env:ChocolateyInstall = [Environment]::GetEnvironmentVariable("ChocolateyInstall","Machine")
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

if (-not (Test-Path $InstallDir)) {
    Write-Warning "Chocolatey installation path not found: $InstallDir"
    return @{ updated = $false; error = "Path not found" }
}

if ($env:path -notlike "*$InstallDir*") {
    $env:Path += ";$InstallDir"
    Write-Host "Added Chocolatey to current session PATH"
    return @{ updated = $true; path = $InstallDir }
} else {
    Write-Host "Chocolatey already in PATH"
    return @{ updated = $false; path = $InstallDir }
} 