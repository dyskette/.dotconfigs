#Requires -Version 7
<#
.SYNOPSIS
Enables WSL, or installs a WSL distribution. Opt-in (Install-WindowsEnvironment.ps1 -InstallWSL).

.DESCRIPTION
Run twice by the orchestrator:

-FeaturesOnly   Enables the Microsoft-Windows-Subsystem-Linux and
                VirtualMachinePlatform features. Returns RestartRequired when
                Windows needs a reboot before a distribution can install; the
                orchestrator stops there and the same command continues after
                the restart. Never reboots on its own.

(default)       Updates WSL itself ('wsl --update'), installs the distribution
                when it is missing (no first launch), and makes it the default.

Both write the WSLg settings into ~/.wslconfig and ~/.wslgconfig by merging
keys: other settings in those files are kept, and the file is backed up once
before its first change.

wsl.exe prints UTF-16 by default; WSL_UTF8=1 makes its output parseable.

.PARAMETER Distribution
Name as listed by 'wsl --list --online'.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param(
    [switch]$FeaturesOnly,
    [string]$Distribution = 'Ubuntu-24.04',
    [string]$WslConfigPath = (Join-Path $env:USERPROFILE '.wslconfig'),
    [string]$WslgConfigPath = (Join-Path $env:USERPROFILE '.wslgconfig')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

<#
.SYNOPSIS
Sets key=value in an INI section, keeping everything else. Returns $true when the file changed.
#>
function Set-IniValue {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param([string]$Path, [string]$Section, [string]$Key, [string]$Value)

    $lines = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path) { $lines.AddRange([string[]]@(Get-Content -LiteralPath $Path)) }

    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "[$Section]") { $start = $i; break }
    }
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[-1].Trim()) { $lines.Add('') }
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
    } else {
        $end = $lines.Count
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -match '^\[.+\]$') { $end = $i; break }
        }
        $found = $false
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*?)\s*$") {
                if ($Matches[1] -eq $Value) { return $false }
                $lines[$i] = "$Key=$Value"
                $found = $true
                break
            }
        }
        if (-not $found) { $lines.Insert($end, "$Key=$Value") }
    }

    if (-not $PSCmdlet.ShouldProcess($Path, "Set [$Section] $Key=$Value")) { return $false }
    if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath "$Path.dotconfigs-backup")) {
        Copy-Item -LiteralPath $Path -Destination "$Path.dotconfigs-backup"
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8NoBOM
    return $true
}

<#
.SYNOPSIS
Writes the WSLg settings; returns the names of files that changed.
#>
function Set-WslgConfig {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([string]$WslConfig, [string]$WslgConfig)

    $changed = @(
        Set-IniValue -Path $WslConfig -Section 'wsl2' -Key 'guiApplications' -Value 'true'
        # HiDPI: let Windows scale WSLg windows instead of fractional RDP scaling.
        Set-IniValue -Path $WslgConfig -Section 'system-distro-env' -Key 'WESTON_RDP_DISABLE_FRACTIONAL_HI_DPI_SCALING' -Value 'true'
        Set-IniValue -Path $WslgConfig -Section 'system-distro-env' -Key 'WESTON_RDP_FRACTIONAL_HI_DPI_SCALING' -Value 'false'
    )
    $names = @()
    if ($changed[0]) { $names += Split-Path $WslConfig -Leaf }
    if ($changed[1] -or $changed[2]) { $names += Split-Path $WslgConfig -Leaf }
    return $names
}

<#
.SYNOPSIS
Runs wsl.exe with UTF-8 output.
#>
function Invoke-Wsl([string[]]$Arguments, [switch]$NoThrow) {
    $previous = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    try {
        return Invoke-Native -FilePath wsl.exe -Arguments $Arguments -Quiet -NoThrow:$NoThrow
    } finally {
        $env:WSL_UTF8 = $previous
    }
}

<#
.SYNOPSIS
Installed distribution names.
#>
function Get-WslDistribution {
    $result = Invoke-Wsl -Arguments @('--list', '--quiet') -NoThrow
    # Exit code is non-zero when no distribution is installed yet.
    @($result.Output | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

if (-not (Test-IsAdministrator)) {
    return New-StepResult Failed 'WSL setup needs Administrator (the WSL steps are marked Admin in steps.psd1).'
}

if ($FeaturesOnly) {
    $enabled = @()
    $restart = $false
    foreach ($feature in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform') {
        $state = Get-WindowsOptionalFeature -Online -FeatureName $feature
        if ($state.State -eq 'Enabled') { continue }
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -All
        $enabled += $feature
        if ($result.RestartNeeded) { $restart = $true }
    }
    $configs = @(Set-WslgConfig -WslConfig $WslConfigPath -WslgConfig $WslgConfigPath)

    if ($restart) {
        return New-StepResult RestartRequired "Enabled $($enabled -join ', '). Restart Windows, then run the same command again." -Data @{ Enabled = $enabled }
    }
    if ($enabled.Count -gt 0 -or $configs.Count -gt 0) {
        return New-StepResult Success "Enabled: $(@($enabled + $configs) -join ', ')." -Data @{ Enabled = $enabled; Configs = $configs }
    }
    return New-StepResult Skipped 'The WSL features are enabled.'
}

$changes = @()
$update = Invoke-Wsl -Arguments @('--update') -NoThrow
if (-not $update.Succeeded) {
    Write-Warning "wsl --update exited with $($update.ExitCode): $(($update.Output | Select-Object -Last 3) -join ' / ')"
}

if ($Distribution -notin (Get-WslDistribution)) {
    Write-Action "Installing $Distribution (no first launch; run 'wsl -d $Distribution' to create your user)..."
    Invoke-Wsl -Arguments @('--install', '--distribution', $Distribution, '--no-launch') | Out-Null
    if ($Distribution -notin (Get-WslDistribution)) {
        return New-StepResult Failed "wsl --install reported success but $Distribution is not listed. Try: wsl --install -d $Distribution"
    }
    $changes += "installed $Distribution"
}

$default = Invoke-Wsl -Arguments @('--set-default', $Distribution) -NoThrow
if (-not $default.Succeeded) {
    return New-StepResult Failed "Could not make $Distribution the default distribution (exit $($default.ExitCode))."
}
$changes += @(Set-WslgConfig -WslConfig $WslConfigPath -WslgConfig $WslgConfigPath | ForEach-Object { "updated $_" })

$data = @{ Changes = $changes; UpdateExitCode = $update.ExitCode }
if (-not $update.Succeeded) {
    return New-StepResult Partial "$Distribution is ready, but 'wsl --update' failed (exit $($update.ExitCode))." -Data $data
}
if ($changes.Count -eq 0) {
    return New-StepResult Skipped "$Distribution is installed and the default." -Data $data
}
return New-StepResult Success "$($changes -join '; ')." -Data $data
