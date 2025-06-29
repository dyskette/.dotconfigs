# Ensure script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
    Write-Error "This script must be run as Administrator."
    Exit 1
}

# 1. Install AutoHotkey v2 via winget
Write-Host "Installing AutoHotkey v2 via winget..."
# Use exact ID and accept agreements for unattended install
Start-Process -FilePath "winget" -ArgumentList "install --exact --id AutoHotkey.AutoHotkey --silent --accept-package-agreements --accept-source-agreements" -Wait

# 2. Download the window-switcher repository ZIP and extract
$baseDir = "C:\AutoHotkey"
$wsDir = Join-Path $baseDir "window-switcher"
$zipUrl = "https://github.com/dyskette/window-switcher/archive/refs/heads/main.zip"
$zipFile = Join-Path $env:TEMP "window-switcher.zip"

Write-Host "Downloading window-switcher repository from GitHub..."
# Remove any existing files/directories from prior run
If (Test-Path $zipFile) { Remove-Item $zipFile -Force }
If (Test-Path $wsDir) { Remove-Item $wsDir -Recurse -Force }
If (Test-Path (Join-Path $baseDir "window-switcher-main")) { Remove-Item (Join-Path $baseDir "window-switcher-main") -Recurse -Force }

# Create base directory if needed
If (-Not (Test-Path $baseDir)) {
    New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
}

# Download and extract
Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile
Expand-Archive -Path $zipFile -DestinationPath $baseDir -Force
# Rename the extracted folder to 'window-switcher'
Rename-Item -Path (Join-Path $baseDir "window-switcher-main") -NewName "window-switcher"

# 3. Register scheduled tasks to run the scripts at logon with highest privileges
# Determine AutoHotkey executable path
$ahkExe = (Get-Command "AutoHotkey.exe" -ErrorAction SilentlyContinue).Path
If (-Not $ahkExe) {
    # Fallback to default path if not in PATH
    $ahkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
}
If (-Not (Test-Path $ahkExe)) {
    Write-Error "AutoHotkey executable not found. Ensure AutoHotkey v2 was installed correctly."
    Exit 1
}

Write-Host "Registering scheduled tasks for window-switcher and app-switcher..."

# Get the Security Identifier (SID) for the built-in Administrators group
$administratorsSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)

# Translate the SID to the correct, localized name for the Administrators group on the current system.
# The resulting variable, $administratorsGroup, will hold a value like "BUILTIN\Administrators" or "BUILTIN\Administratoren".
$administratorsGroup = $administratorsSid.Translate([System.Security.Principal.NTAccount]).Value

# Define common trigger at logon
$trigger = New-ScheduledTaskTrigger -AtLogOn

# Define principal to run as Administrators group with highest privileges:contentReference[oaicite:9]{index=9}
$principal = New-ScheduledTaskPrincipal -GroupId $administratorsGroup -RunLevel Highest

# Window Switcher task
$winSwitcherAction = New-ScheduledTaskAction -Execute $ahkExe -Argument (Join-Path $wsDir "window-switcher.ahk")
Register-ScheduledTask -TaskName "Window Switcher (AHK)" `
    -Action $winSwitcherAction -Trigger $trigger -Principal $principal -Force

# Application Switcher task
$appSwitcherAction = New-ScheduledTaskAction -Execute $ahkExe -Argument (Join-Path $wsDir "app-switcher.ahk")
Register-ScheduledTask -TaskName "App Switcher (AHK)" `
    -Action $appSwitcherAction -Trigger $trigger -Principal $principal -Force

$taskNames = @(
    "Window Switcher (AHK)",
    "App Switcher (AHK)"
)

Write-Host "Checking status of registered tasks..."

foreach ($taskName in $taskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($task) {
        if ($task.State -ne 'Running') {
            Write-Host "Task '$taskName' is not running. Starting it now..."
            Start-ScheduledTask -TaskName $taskName
        } else {
            Write-Host "Task '$taskName' is already running."
        }
    } else {
        Write-Host "Could not find task '$taskName'. It may not have registered correctly." -ForegroundColor Yellow
    }
}

Write-Host "Setup complete. Tasks are configured to run at startup and have been started for the current session."
