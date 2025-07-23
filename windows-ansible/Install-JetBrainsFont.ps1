function InstallJetBrainsMonoFonts {
    param (
        [string]$fontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz",
        [string]$localAppData = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    )

    $fontFilesPattern = "JetBrainsMonoNLNerdFont-*.ttf"
    $tempDir = [System.IO.Path]::GetTempPath()
    $fontTarPath = "$tempDir\JetBrainsMono.tar.xz"
    $fontFolder = "$tempDir\JetBrainsMono"
    $regPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

    # Check if fonts are already installed
    $existingFonts = Get-ChildItem -Path $localAppData -Filter $fontFilesPattern -ErrorAction SilentlyContinue
    if ($existingFonts.Count -gt 0) {
        Write-Host "JetBrains Mono NL Nerd Fonts are already installed. Skipping installation."
        return @{
            status = "already_installed"
            message = "Fonts already present"
            installed_count = $existingFonts.Count
        }
    }

    Write-Host "Installing JetBrains Mono NL Nerd Fonts..."

    # Download the fonts
    if (Test-Path -Path $fontTarPath) {
        Remove-Item -Path $fontTarPath -Force
        Write-Host "Existing download $fontTarPath removed."
    }

    try {
        Invoke-WebRequest -Uri $fontUrl -OutFile $fontTarPath
    } catch {
        Write-Error "Failed to download fonts: $($_.Exception.Message)"
        return @{
            status = "error"
            message = "Download failed: $($_.Exception.Message)"
        }
    }

    if (Test-Path -Path $fontFolder) {
        Remove-Item -Path $fontFolder -Recurse -Force
        Write-Host "Existing directory $fontFolder removed."
    }

    New-Item -Path $fontFolder -ItemType Directory -Force

    try {
        tar -xf $fontTarPath -C $fontFolder
    } catch {
        Write-Error "Failed to extract fonts: $($_.Exception.Message)"
        return @{
            status = "error"
            message = "Extraction failed: $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path -Path $localAppData)) {
        New-Item -Path $localAppData -ItemType Directory -Force
    }

    # Copy the fonts
    Remove-Item -Path "$localAppData\$fontFilesPattern" -Force -ErrorAction SilentlyContinue
    
    try {
        Copy-Item -Path "$fontFolder\$fontFilesPattern" -Destination $localAppData -Force
    } catch {
        Write-Error "Failed to copy fonts: $($_.Exception.Message)"
        return @{
            status = "error"
            message = "Font copy failed: $($_.Exception.Message)"
        }
    }

    # Add to registry
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force
    }

    $fontFiles = Get-ChildItem -Path $localAppData -Filter "$fontFilesPattern"
    $installedCount = 0

    foreach ($fontFile in $fontFiles) {
        try {
            $fontRegName = [System.IO.Path]::GetFileNameWithoutExtension($fontFile.Name) + " (TrueType)"
            Set-ItemProperty -Path $regPath -Name $fontRegName -Value $fontFile.FullName -Type String
            $installedCount++
            Write-Host "Registered font: $fontRegName"
        } catch {
            Write-Warning "Failed to register font $($fontFile.Name): $($_.Exception.Message)"
        }
    }

    # Broadcast the WM_FONTCHANGE message to other applications
    $fontChangeCode = @"
    using System;
    using System.Runtime.InteropServices;
    public class User32 {
        [return: MarshalAs(UnmanagedType.Bool)]
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern bool PostMessage(IntPtr hWnd, int Msg, int wParam = 0, int lParam = 0);
    }
"@
    Add-Type -TypeDefinition $fontChangeCode
    $broadcastHandle = [IntPtr]::Zero
    $wmFontChange = 0x1D
    $broadcastResult = [User32]::PostMessage($broadcastHandle, $wmFontChange)

    if ($broadcastResult) {
        Write-Host "Broadcasted font change to applications."
    } else {
        Write-Host "Unable to broadcast font change to applications. Restart might be necessary."
    }

    # Cleanup
    if (Test-Path -Path $fontTarPath) {
        Remove-Item -Path $fontTarPath -Force
    }
    if (Test-Path -Path $fontFolder) {
        Remove-Item -Path $fontFolder -Recurse -Force
    }

    return @{
        status = "installed"
        message = "Successfully installed JetBrains Mono NL Nerd Fonts"
        installed_count = $installedCount
        broadcast_success = $broadcastResult
    }
}

# Execute the function and return result
$result = InstallJetBrainsMonoFonts
Write-Host "Installation result: $($result.message)"
return $result 