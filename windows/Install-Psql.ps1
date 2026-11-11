#Requires -Version 7
<#
.SYNOPSIS
Installs or upgrades the PostgreSQL command line tools (psql) without the server.

.DESCRIPTION
There is no client-only winget package, so the EDB installer is told to skip
the server, pgAdmin and StackBuilder. That needs --override, which winget import
does not support; --override also replaces winget's own silent switches, so the
unattended mode is restated. The installer never touches PATH, so the bin folder
is added to the user PATH afterwards.

The major version is pinned (steps.psd1). Within it, the installed psql version
is compared with 'winget show' and the installer re-runs when a newer build
exists; otherwise nothing happens.

Troubleshooting: a VPN that answers DNS itself and tunnels broad public ranges
can break the download. get.enterprisedb.com is on CloudFront, the VPN's
resolver may return an edge address inside a tunnelled range (seen with
99.0.0.0/8), and the tunnel drops it. winget then fails with 0x80072EE2
(timeout) before the installer starts. Disconnect the VPN and run again.

.PARAMETER Version
PostgreSQL major version.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

$packageId = "PostgreSQL.PostgreSQL.$Version"
$pgBin = Join-Path $env:ProgramFiles "PostgreSQL\$Version\bin"
$psqlPath = Join-Path $pgBin 'psql.exe'

<#
.SYNOPSIS
"psql (PostgreSQL) 18.6" -> [version] 18.6, or $null.
#>
function Get-InstalledPsqlVersion {
    if (-not (Test-Path -LiteralPath $psqlPath)) { return $null }
    $output = (Invoke-Native -FilePath $psqlPath -Arguments @('--version') -Quiet -NoThrow).Output | Select-Object -First 1
    if ("$output" -match '(\d+\.\d+)') { return [version]$Matches[1] }
    return $null
}

<#
.SYNOPSIS
Latest version winget offers for the package ("Version: 18.6-5" -> 18.6), or $null.
#>
function Get-AvailablePsqlVersion {
    $show = Invoke-Native -FilePath winget -Quiet -NoThrow -Arguments @(
        'show', '--exact', '--id', $packageId, '--accept-source-agreements')
    $line = $show.Output | Where-Object { $_ -match '^Version:\s*(\d+\.\d+)' } | Select-Object -First 1
    if ($line -and $line -match '^Version:\s*(\d+\.\d+)') { return [version]$Matches[1] }
    return $null
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    return New-StepResult Failed 'winget is not on PATH.'
}

$installed = Get-InstalledPsqlVersion
$available = Get-AvailablePsqlVersion
if ($installed -and -not $available) {
    [void](Add-PathEntry -Path $pgBin)
    return New-StepResult Failed "psql $installed is installed, but winget did not report the latest $packageId; cannot check for updates."
}
if ($installed -and $installed -ge $available) {
    [void](Add-PathEntry -Path $pgBin)
    return New-StepResult Skipped "psql $installed is up to date." -Data @{ Version = "$installed" }
}

# The EDB installer writes to Program Files. Without elevation winget would have
# to raise a UAC prompt, which an unattended override may never get to show.
if (-not (Test-IsAdministrator)) {
    return New-StepResult Failed 'Installing psql needs Administrator (the Psql step is marked Admin in steps.psd1).'
}

$logDir = New-WorkDirectory -Prefix 'install-psql'
$wingetLog = Join-Path $logDir 'winget.log'
# EDB/BitRock write their own logs to %TEMP%; anything newer than this is ours.
$startedAt = Get-Date

Write-Action ($installed ? "Upgrading psql $installed -> $available..." : "Installing psql $available (PostgreSQL $Version client only)...")
# 'install' also upgrades an installed package when a newer version exists.
$exitCode = Invoke-Winget -Arguments @(
    'install', '--exact', '--id', $packageId,
    '--accept-package-agreements', '--accept-source-agreements',
    '--verbose-logs', '--log', $wingetLog,
    '--override', '--mode unattended --unattendedmodeui none --disable-components server,pgAdmin,stackbuilder'
)

$installerLogs = @(Get-ChildItem -LiteralPath $env:TEMP -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $startedAt -and $_.Name -match 'postgres|bitrock' } |
        ForEach-Object FullName)
$logs = @($wingetLog) + $installerLogs
$logNote = if ($installerLogs) { '' } else { ' No EDB installer log appeared in %TEMP%, so the installer may not have started.' }

if ($exitCode -ne 0) {
    return New-StepResult Failed ('winget exited with {0} (0x{0:X8}).{1} Logs: {2}' -f $exitCode, $logNote, ($logs -join ', ')) `
        -Data @{ ExitCode = $exitCode; Logs = $logs }
}

$now = Get-InstalledPsqlVersion
if (-not $now) {
    return New-StepResult Failed "winget reported success but $psqlPath does not exist.$logNote Logs: $($logs -join ', ')"
}
[void](Add-PathEntry -Path $pgBin)
Remove-Item -LiteralPath $logDir -Recurse -Force -ErrorAction SilentlyContinue # safe: private log dir from New-WorkDirectory, not needed after success

$from = if ($installed) { " (was $installed)" } else { '' }
return New-StepResult Success "psql $now installed$from." -Data @{ Version = "$now"; Previous = "$installed" }
