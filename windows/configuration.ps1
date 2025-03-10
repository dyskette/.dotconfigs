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

function CreateWindowsTerminalDotfiles
{
    param (
        [string]$dotfilesPath = "$(Split-Path -Parent $PSScriptRoot)\windows_terminal",
        [string]$windowsTerminalConfigPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
    )

    if (-not(Test-Path -Path $windowsTerminalConfigPath))
    {
        Write-Host "Created windows terminal configuration directory"
        New-Item -Path $windowsTerminalConfigPath -ItemType Directory -Force
    }
    else {
        Write-Host "Existing file $windowsTerminalConfigPath\settings.json removed."
        Remove-Item -Path "$windowsTerminalConfigPath\settings.json" -Force
    }

    New-Item -Path "$windowsTerminalConfigPath\settings.json" -Target "$dotfilesPath\settings.json" -ItemType SymbolicLink
    Write-Host "Link created from $dotfilesPath\settings.json to $windowsTerminalConfigPath\settings.json."
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

function InstallTmux {
    # Names
    $zstd = "zstd-v1.5.7-win64"
    $tmux = "tmux-3.5.a-2-x86_64"
    $libevent = "libevent-2.1.12-4-x86_64"
    $gitusrbin = "C:\Program Files\Git\usr\bin\"

    if (Test-Path "$env:TEMP\$zstd.zip") {
        Remove-Item -Force "$env:TEMP\$zstd.zip"
    }

    if (Test-Path "$env:TEMP\$tmux.pkg.tar.zst") {
        Remove-Item -Force "$env:TEMP\$tmux.pkg.tar.zst"
    }

    if (Test-Path "$env:TEMP\$libevent.pkg.tar.zst") {
        Remove-Item -Force "$env:TEMP\$libevent.pkg.tar.zst"
    }

    # Download files
    & curl -sSL "https://github.com/facebook/zstd/releases/download/v1.5.7/$zstd.zip" -o "$env:TEMP\$zstd.zip"
    Expand-Archive -Force "$env:TEMP\$zstd.zip" -DestinationPath "$env:TEMP"
    $zstdExe = "$env:TEMP\$zstd\zstd.exe"
    & curl -sSL "https://mirror.msys2.org/msys/x86_64/$tmux.pkg.tar.zst" -o "$env:TEMP\$tmux.pkg.tar.zst"
    & curl -sSL "https://mirror.msys2.org/msys/x86_64/$libevent.pkg.tar.zst" -o "$env:TEMP\$libevent.pkg.tar.zst"

    if (Test-Path "$env:TEMP\$tmux.pkg.tar") {
        Remove-Item -Force "$env:TEMP\$tmux.pkg.tar"
    }

    if (Test-Path "$env:TEMP\$libevent.pkg.tar") {
        Remove-Item -Force "$env:TEMP\$libevent.pkg.tar"
    }

    # Decompress files
    & $zstdExe --quiet --decompress "$env:TEMP\$tmux.pkg.tar.zst"
    & $zstdExe --quiet --decompress "$env:TEMP\$libevent.pkg.tar.zst"

    if (Test-Path "$env:TEMP\$tmux") {
        Remove-Item -Recurse -Force "$env:TEMP\$tmux"
    }

    if (Test-Path "$env:TEMP\$libevent") {
        Remove-Item -Recurse -Force "$env:TEMP\$libevent"
    }

    New-Item -ItemType Directory "$env:TEMP\$tmux"
    New-Item -ItemType Directory "$env:TEMP\$libevent"

    # Decompress again
    & tar -xf "$env:TEMP\$tmux.pkg.tar" --directory "$env:TEMP\$tmux"
    & tar -xf "$env:TEMP\$libevent.pkg.tar" --directory "$env:TEMP\$libevent"

    Remove-Item -Force -Path "$gitusrbin\tmux.exe"
    Remove-Item -Force -Path "$gitusrbin\*" -Include "msys-event*.dll", "event_rpcgen.py"

    # Copy binaries into git /usr/bin directory
    Copy-Item -Path "$env:TEMP\$tmux\usr\bin\tmux.exe" -Destination "$gitusrbin"
    Copy-Item -Path "$env:TEMP\$libevent\usr\bin\*" -Destination "$gitusrbin" -Include "msys-event*.dll", "event_rpcgen.py"
}
