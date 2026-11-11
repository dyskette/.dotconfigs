#Requires -Version 7
<#
.SYNOPSIS
Applies the per-user Windows settings in the table below.

.DESCRIPTION
Every setting lives under HKCU, so this runs as the current user. Each value is
written only when it differs, then read back, so the result reports what really
changed. Explorer picks most of these up when its windows refresh; some need
signing out or restarting Explorer, which this script does not do on its own.

.PARAMETER AdvancedKey
Explorer's Advanced settings key. A parameter so tests can use a scratch key.

.OUTPUTS
Dotconfigs.StepResult: Skipped when everything was already set, Success when
values changed, Partial or Failed when some could not be written.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AdvancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

$advanced = $AdvancedKey
$settings = @(
    @{ Path = $advanced; Name = 'HideFileExt'; Value = 0; Description = 'Show file extensions' }
    @{ Path = $advanced; Name = 'Hidden'; Value = 1; Description = 'Show hidden files' }
    @{ Path = $advanced; Name = 'VirtualDesktopTaskbarFilter'; Value = 0; Description = 'Taskbar shows windows from all desktops' }
    @{ Path = $advanced; Name = 'VirtualDesktopAltTabFilter'; Value = 0; Description = 'Alt+Tab shows windows from all desktops' }
    # Settings > System > Multitasking > "Show tabs from apps when snapping or
    # pressing Alt+Tab": 1 = 5 recent tabs, 2 = 3 recent tabs, 3 = don't show
    # tabs. Microsoft documents only the equivalent policy, BrowserAltTabBlowout
    # (Policy CSP - Multitasking, 4 = open windows only), which lives under
    # HKCU\Software\Policies and needs Administrator; this per-user value is
    # what the Settings app writes (mapping per WinAero / ElevenForum).
    @{ Path = $advanced; Name = 'MultiTaskingAltTabFilter'; Value = 3; Description = 'Alt+Tab shows windows, not browser tabs' }
)

$changed = [Collections.Generic.List[string]]::new()
$failed = [Collections.Generic.List[string]]::new()

foreach ($setting in $settings) {
    try {
        $current = (Get-Item -Path $setting.Path -ErrorAction SilentlyContinue)?.GetValue($setting.Name)
        if ($null -ne $current -and $current -eq $setting.Value) { continue }

        if (-not $PSCmdlet.ShouldProcess("$($setting.Path)\$($setting.Name)", "Set to $($setting.Value)")) { continue }
        if (-not (Test-Path -Path $setting.Path)) { New-Item -Path $setting.Path -Force | Out-Null }
        Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type DWord

        $readBack = (Get-Item -Path $setting.Path).GetValue($setting.Name)
        if ($readBack -ne $setting.Value) {
            throw "read back $readBack after writing $($setting.Value)"
        }
        Write-Info "Set: $($setting.Description)"
        $changed.Add($setting.Description)
    } catch {
        Write-Warning "$($setting.Description): $($_.Exception.Message)"
        $failed.Add("$($setting.Description) ($($_.Exception.Message))")
    }
}

if ($changed.Count -gt 0) {
    # Lets Explorer and other shell windows re-read their settings.
    [void](Send-BroadcastMessage -Message 0x1A -Parameter 'ShellState')
}

$data = @{ Changed = $changed.ToArray(); Failed = $failed.ToArray() }
if ($failed.Count -gt 0) {
    $status = if ($changed.Count -gt 0) { 'Partial' } else { 'Failed' }
    return New-StepResult $status "Could not apply: $($failed -join '; ')." -Data $data
}
if ($changed.Count -eq 0) {
    return New-StepResult Skipped "All $($settings.Count) settings were already applied." -Data $data
}
return New-StepResult Success "Applied $($changed.Count) setting(s); some take effect after Explorer restarts or you sign out." -Data $data
