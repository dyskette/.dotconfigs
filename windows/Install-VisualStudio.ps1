#Requires -Version 7
<#
.SYNOPSIS
Installs Visual Studio, or adds the components from vs/vsconfig.jsonc to an
existing installation.

.DESCRIPTION
Three cases:
- Every declared component is present: nothing to do (vswhere -requires matches
  only installations that have all of them).
- The product is installed but incomplete: the VS Installer's 'modify' verb adds
  the missing components. The bootstrapper's 'install' verb cannot be used here:
  when the product exists it exits with 1 before reading --config, leaving the
  components uninstalled.
- Not installed: winget installs it with the configuration.

The installer parses --config as strict JSON, so the commented .jsonc is
rewritten to a plain .vsconfig first.

.PARAMETER Product
vswhere product ID.

.PARAMETER WingetId
winget package ID used for a fresh install.

.PARAMETER VersionRange
vswhere version range the installation must fall in.

.PARAMETER ConfigPath
Component manifest. Defaults to vs/vsconfig.jsonc in the repo.

.OUTPUTS
Dotconfigs.StepResult. Exit code 3010 (reboot pending) is a Success with
Data.RestartRecommended, since the tools are usable before the reboot.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Product,
    [Parameter(Mandatory)][string]$WingetId,
    [Parameter(Mandatory)][string]$VersionRange,
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'vs\vsconfig.jsonc')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

$installerDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'
$vswhere = Join-Path $installerDir 'vswhere.exe'

<#
.SYNOPSIS
Installation path of the newest matching instance, optionally requiring components.
#>
function Find-VsInstance {
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$Range,
        [string[]]$Requires = @()
    )

    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
    $arguments = @('-latest', '-products', $ProductId, '-version', $Range)
    if ($Requires) { $arguments += @('-requires') + $Requires }
    $arguments += @('-property', 'installationPath')
    (Invoke-Native -FilePath $vswhere -Arguments $arguments -Quiet).Output | Where-Object { $_ } | Select-Object -First 1
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    return New-StepResult Failed "Configuration not found: $ConfigPath"
}
$components = @((Read-Jsonc $ConfigPath).components)
if ($components.Count -eq 0) {
    return New-StepResult Failed "$ConfigPath declares no components."
}

$installPath = Find-VsInstance -ProductId $Product -Range $VersionRange
if ($installPath -and (Find-VsInstance -ProductId $Product -Range $VersionRange -Requires $components)) {
    return New-StepResult Skipped "All $($components.Count) components are already installed at $installPath."
}

$workDir = New-WorkDirectory -Prefix 'dotconfigs-vs'
try {
    $vsconfig = Join-Path $workDir 'dotconfigs.vsconfig'
    [ordered]@{ version = '1.0'; components = $components } |
        ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $vsconfig -Encoding utf8NoBOM

    if ($installPath) {
        Write-Action "Adding missing components to $installPath. This downloads several GB; the installer shows its own progress."
        # setup.exe is a GUI-subsystem program: the call operator would not wait
        # for it, so Start-Process -Wait does. 'modify' rejects --wait.
        $arguments = @('modify', '--installPath', $installPath, '--config', $vsconfig, '--passive', '--norestart')
        $commandLine = ($arguments | ForEach-Object { ConvertTo-CommandLineArgument $_ }) -join ' '
        $exitCode = (Start-Process -FilePath (Join-Path $installerDir 'setup.exe') -ArgumentList $commandLine -Wait -PassThru).ExitCode
    } else {
        Write-Action "Installing $WingetId. This downloads several GB; the installer shows its own progress."
        $override = '--wait --passive --norestart --config ' + (ConvertTo-CommandLineArgument $vsconfig)
        $exitCode = Invoke-Winget -Arguments @(
            'install', '--exact', '--id', $WingetId, '--silent',
            '--accept-package-agreements', '--accept-source-agreements', '--override', $override
        )
    }
} finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue # safe: private temp dir from New-WorkDirectory
}

switch ($exitCode) {
    0 { return New-StepResult Success 'Visual Studio has every component from vsconfig.' }
    3010 {
        return New-StepResult Success 'Components installed; a restart is pending.' -Data @{ RestartRecommended = $true }
    }
    default {
        return New-StepResult Failed ('Setup exited with {0}. Installer logs: {1}' -f
            $exitCode, (Join-Path $env:TEMP 'dd_installer_*.log')) -Data @{ ExitCode = $exitCode }
    }
}
