function UpdateChocolateyEnvironmentVariables
{
    $InstallDir = "C:\ProgramData\chocolatey"
    $env:ChocolateyInstall = [Environment]::GetEnvironmentVariable("ChocolateyInstall","Machine")
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    if ($env:path -notlike "*$InstallDir*")
    {
        $env:Path += ";$InstallDir"
    }
}

function CreatePowerShellProfile
{
    param (
        [string]$dotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\PowerShell\",
        [string]$powershellProfilePath = "$env:USERPROFILE\Documents\PowerShell\"
    )

    if (Test-Path -Path $powershellProfilePath)
    {
        Remove-Item -Path $powershellProfilePath -Recurse -Force
        Write-Host "Existing directory $powershellProfilePath removed."
    }

    New-Item -Path $powershellProfilePath -Value $dotfilesPath -ItemType Junction
    Write-Host "Link created from $dotfilesPath to $powershellProfilePath."
}

function CreateBatDotfiles
{
    param(
        [string]$dotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\bat",
        [string]$batConfigPath = "$env:APPDATA\bat"
    )

    # Update PATH environment variable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (Test-Path -Path $batConfigPath)
    {
        Remove-Item -Path $batConfigPath -Recurse -Force
        Write-Host "Existing directory $batConfigPath removed."
    }

    New-Item -Path $batConfigPath -Value $dotfilesPath -ItemType Junction
    Write-Host "Link created from $dotfilesPath to $batConfigPath"

    bat cache --build
}

function CreateNvimDotfiles
{
    param (
        [string]$dotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\nvim\",
        [string]$nvimConfigPath = "$env:LOCALAPPDATA\nvim\"
    )

    if (Test-Path -Path $nvimConfigPath)
    {
        Remove-Item -Path $nvimConfigPath -Recurse -Force
        Write-Host "Existing directory $nvimConfigPath removed."
    }

    New-Item -Path $nvimConfigPath -Value $dotfilesPath -ItemType Junction
    Write-Host "Link created from $dotfilesPath to $nvimConfigPath."
}

function CreateWezTermDotfiles
{
    param (
        [string]$dotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\wezterm",
        [string]$weztermConfigPath = "$env:USERPROFILE\.wezterm"
    )

    if (Test-Path -Path $weztermConfigPath)
    {
        Remove-Item -Path $weztermConfigPath -Recurse -Force
        Write-Host "Existing directory $weztermConfigPath removed."
    }

    New-Item -Path $weztermConfigPath -Target $dotfilesPath -ItemType Junction
    Write-Host "Link created from $dotfilesPath to $weztermConfigPath."
}

function CreateVSDotfiles
{
    param (
        [string]$dotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\vs\vsvimrc",
        [string]$vsConfigPath = "$env:USERPROFILE\.vsvimrc"
    )

    if (Test-Path -Path $vsConfigPath)
    {
        Remove-Item -Path $vsConfigPath -Force
        Write-Host "Existing directory $vsConfigPath removed."
    }

    New-Item -Path $vsConfigPath -Target $dotfilesPath -ItemType HardLink
    Write-Host "Link created from $dotfilesPath to $vsConfigPath."
}

function CreateVSCodeDotfiles
{
    param (
        [string]$dotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\vscode",
        [string]$codeUser = "$env:APPDATA\Code\User"
    )

    # Update PATH environment variable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    $settingsSource = Join-Path $dotfilesPath "settings.json" -Resolve
    $settingsTarget = "$codeUser\settings.json"

    $keybindingsSource = Join-Path $dotfilesPath "keybindings.json" -Resolve
    $keybindingsTarget = "$codeUser\keybindings.json"

    if (Test-Path -Path $codeUser)
    {
        Remove-Item -Path $codeUser -Force -Recurse
        Write-Host "Existing directory $codeUser removed."
    }

    New-Item -Path $codeUser -ItemType Directory -Force
    New-Item -Path $settingsTarget -Target $settingsSource -ItemType SymbolicLink
    New-Item -Path $keybindingsTarget -Target $keybindingsSource -ItemType SymbolicLink

    Write-Host "Symbolic links created from $dotfilesPath to $codeUser."
}

function InstallVSCodeExtensions
{
    param (
        [string]$extensionsPath = "$(Split-Path -Parent $PSScriptRoot)\vscode\extensions.json",
        [string]$extensionsTarget = "$env:USERPROFILE\.vscode\extensions"
    )

    # Update PATH environment variable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (Test-Path -Path $extensionsTarget)
    {
        Remove-Item -Path $extensionsTarget -Force -Recurse
        Write-Host "Existing directory $extensionsTarget removed."
    }

    $config = Get-Content -Path $extensionsPath | ConvertFrom-Json

    foreach ($name in $config.extensions)
    {
        code --install-extension $name
    }

    Write-Host "Extensions installed from $extensionsPath."
}

function CreateJetBrainsDotfiles
{
    param (
        [string]$dotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\jetbrains\ideavimrc",
        [string]$jetbrainsConfigPath = "$env:USERPROFILE\.ideavimrc"
    )

    if (Test-Path -Path $jetbrainsConfigPath)
    {
        Remove-Item -Path $jetbrainsConfigPath -Force
        Write-Host "Existing directory $jetbrainsConfigPath removed."
    }

    New-Item -Path $jetbrainsConfigPath -Target $dotfilesPath -ItemType SymbolicLink
    Write-Host "Link created from $dotfilesPath to $jetbrainsConfigPath."
}

function InstallJetBrainsMonoFonts
{
    param (
        [string]$fontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/JetBrainsMono.tar.xz",
        [string]$localAppData = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    )

    $fontFilesPattern = "JetBrainsMonoNLNerdFont-*.ttf"
    $tempDir = [System.IO.Path]::GetTempPath()
    $fontTarPath = "$tempDir\JetBrainsMono.tar.xz"
    $fontFolder = "$tempDir\JetBrainsMono"
    $regPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

    # Download the fonts

    if (Test-Path -Path $fontTarPath)
    {
        Remove-Item -Path $fontTarPath -Force
        Write-Host "Existing download $fontTarPath removed."
    }

    Invoke-WebRequest -Uri $fontUrl -OutFile $fontTarPath

    if (Test-Path -Path $fontFolder)
    {
        Remove-Item -Path $fontFolder -Recurse -Force
        Write-Host "Existing directory $fontFolder removed."
    }

    New-Item -Path $fontFolder -ItemType Directory -Force
    tar -xf $fontTarPath -C $fontFolder

    if (-not (Test-Path -Path $localAppData))
    {
        New-Item -Path $localAppData -ItemType Directory -Force
    }

    # Copy the fonts

    Remove-Item -Path "$localAppData\$fontFilesPattern" -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$fontFolder\$fontFilesPattern" -Destination $localAppData -Force

    # Add to registry

    if (-not (Test-Path $regPath))
    {
        New-Item -Path $regPath -Force
    }

    $fontFiles = Get-ChildItem -Path $localAppData -Filter "$fontFilesPattern"

    foreach ($fontFile in $fontFiles)
    {
        $fontRegName = [System.IO.Path]::GetFileNameWithoutExtension($fontFile.Name) + " (TrueType)"
        Set-ItemProperty -Path $regPath -Name $fontRegName -Value $fontFile.FullName -Type String
    }

    # Broadcast the WM_FONTCHANGE message to other applications
    # HWND_BROADCAST https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-postmessagea
    # WM_FONTCHANGE https://docs.microsoft.com/en-us/windows/win32/gdi/wm-fontchange
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class User32 {
        [return: MarshalAs(UnmanagedType.Bool)]
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern bool PostMessage(IntPtr hWnd, int Msg, int wParam = 0, int lParam = 0);
    }
"@
    $broadcastHandle = [IntPtr]::Zero
    $wmFontChange = 0x1D
    $result = [User32]::PostMessage($broadcastHandle, $wmFontChange)

    if ($result)
    {
        Write-Host "Broadcasted font change to applications."
    } else
    {
        Write-Host "Unable to broadcast font change to applications. Restart might be necessary."
    }
}
