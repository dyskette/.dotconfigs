# Configure Windows settings equivalent to DSC configuration
try {
    Write-Host "Configuring Windows settings..."
    $changesApplied = @()
    $errors = @()

    # Configure Windows Explorer settings
    Write-Host "Configuring Windows Explorer settings..."
    
    try {
        # Enable file extensions
        $explorerKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $explorerKey -Name "HideFileExt" -Value 0 -Force
        $changesApplied += "File extensions enabled"
        
        # Show hidden files
        Set-ItemProperty -Path $explorerKey -Name "Hidden" -Value 1 -Force
        $changesApplied += "Hidden files enabled"
        
        Write-Host "Windows Explorer settings configured successfully."
    } catch {
        $errors += "Failed to configure Windows Explorer: $($_.Exception.Message)"
    }

    # Configure Virtual Desktop settings
    Write-Host "Configuring Virtual Desktop settings..."
    
    try {
        $explorerAdvancedKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        
        # Show all open windows from all desktops in taskbar
        Set-ItemProperty -Path $explorerAdvancedKey -Name "VirtualDesktopTaskbarFilter" -Value 0 -Type DWord -Force
        $changesApplied += "Taskbar shows windows from all desktops"
        
        # Show all open windows from all desktops when pressing Alt+Tab
        Set-ItemProperty -Path $explorerAdvancedKey -Name "VirtualDesktopAltTabFilter" -Value 0 -Type DWord -Force
        $changesApplied += "Alt+Tab shows windows from all desktops"
        
        Write-Host "Virtual Desktop settings configured successfully."
    } catch {
        $errors += "Failed to configure Virtual Desktop settings: $($_.Exception.Message)"
    }

    # Configure browser Alt+Tab behavior (note: may not work due to Windows implementation)
    Write-Host "Configuring browser Alt+Tab behavior..."
    
    try {
        $explorerPolicyKey = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        
        # Create the key if it doesn't exist
        if (-not (Test-Path $explorerPolicyKey)) {
            New-Item -Path $explorerPolicyKey -Force | Out-Null
        }
        
        # Show open windows only in Alt+Tab (may not work as intended)
        Set-ItemProperty -Path $explorerPolicyKey -Name "BrowserAltTabBlowout" -Value 4 -Type DWord -Force
        $changesApplied += "Browser Alt+Tab behavior configured (may require restart)"
        
        Write-Host "Browser Alt+Tab behavior configured (note: may not work due to Windows implementation)."
    } catch {
        $errors += "Failed to configure browser Alt+Tab behavior: $($_.Exception.Message)"
    }

    # Notify Explorer of registry changes without restarting it
    Write-Host "Broadcasting settings change to Explorer..."
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
"@
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x001A
        $SMTO_ABORTIFHUNG = 0x0002
        $result = [UIntPtr]::Zero
        [Win32]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", $SMTO_ABORTIFHUNG, 5000, [ref]$result) | Out-Null
        $changesApplied += "Settings change broadcast sent"
    } catch {
        $errors += "Failed to broadcast settings change: $($_.Exception.Message)"
    }

    # Return results
    $result = @{
        status = if ($errors.Count -eq 0) { "success" } else { "partial" }
        message = "Windows configuration completed"
        changes_applied = $changesApplied
        errors = $errors
        restart_recommended = $true
    }

    Write-Host "Windows configuration completed successfully!"
    if ($changesApplied.Count -gt 0) {
        Write-Host "Changes applied:"
        $changesApplied | ForEach-Object { Write-Host "  - $_" }
    }
    
    if ($errors.Count -gt 0) {
        Write-Warning "Some errors occurred:"
        $errors | ForEach-Object { Write-Warning "  - $_" }
    }
    
    Write-Host "Note: Some changes may require a restart to take full effect."
    
    return $result

} catch {
    Write-Error "Error configuring Windows settings: $($_.Exception.Message)"
    return @{
        status = "error"
        message = "Error configuring Windows settings: $($_.Exception.Message)"
        changes_applied = @()
        errors = @($_.Exception.Message)
    }
} 