#Requires -Version 7
<#
.SYNOPSIS
Installs the winget packages listed in packages.jsonc.

.DESCRIPTION
Runs 'winget import'. Its exit code only says that something failed, not what,
so the whole import is retried (already-installed packages are skipped on each
attempt). Per-package installer logs are in winget's DiagOutputDir.

.PARAMETER ManifestPath
winget export/import manifest. Defaults to packages.jsonc next to this script.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'packages.jsonc')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    return New-StepResult Failed "Manifest not found: $ManifestPath"
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    return New-StepResult Failed 'winget is not on PATH.'
}

$exitCode = Invoke-Winget -RetryOnAnyExitCode -Arguments @(
    'import', '--import-file', $ManifestPath,
    '--accept-package-agreements', '--accept-source-agreements', '--ignore-unavailable'
)

if ($exitCode -eq 0) {
    return New-StepResult Success 'All packages are installed.'
}

$diagnostics = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir'
return New-StepResult Partial ('winget import exited with {0} (0x{0:X8}): one or more packages failed. Logs: {1}' -f
    $exitCode, $diagnostics) -Data @{ ExitCode = $exitCode }
