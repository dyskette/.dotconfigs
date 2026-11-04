#Requires -Version 7
<#
.SYNOPSIS
Installs the PostgreSQL command line tools (psql) without the server.

.DESCRIPTION
There is no client-only winget package, so the EDB installer is told to skip
the server, pgAdmin and StackBuilder. That needs --override, which winget
import does not support, and --override replaces winget's own silent switches,
so the unattended mode is restated here. The installer never touches PATH, so
the bin folder is added to the user PATH afterwards.

It keeps winget's verbose log and points at the EDB installer's own logs, so a
failure can be inspected.

A VPN that answers DNS itself and tunnels broad public ranges can break the
download: get.enterprisedb.com is on CloudFront, the VPN's resolver may return
an edge address inside a tunnelled range (seen with 99.0.0.0/8), and the
tunnel drops it. winget then fails with 0x80072EE2 (timeout) before the
installer starts. Disconnect the VPN and run again.

Run by Install-WindowsEnvironment.ps1 through Invoke-Step, so it returns
@{ status; message } rather than exiting; it can also be run on its own.

.PARAMETER Version
PostgreSQL major version to install.

.OUTPUTS
Hashtable with status ("success" or "error") and message.

.EXAMPLE
./Install-Psql.ps1
#>
[CmdletBinding()]
param(
    [int]$Version = 18
)

$ErrorActionPreference = 'Stop'

$pgBin = "$env:ProgramFiles\PostgreSQL\$Version\bin"
$logDir = Join-Path $env:TEMP "install-psql-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$wingetLog = Join-Path $logDir 'winget.log'

if (Test-Path (Join-Path $pgBin 'psql.exe')) {
    Write-Host "psql already installed at $pgBin. Skipping install." -ForegroundColor Green
} else {
    # The EDB installer writes to Program Files; without elevation winget has to
    # raise a UAC prompt, which an unattended override may not get to show.
    $isAdmin = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Host "Elevated: $isAdmin" -ForegroundColor Cyan

    # Marks the EDB/BitRock logs that appear in %TEMP% during this run.
    $startedAt = Get-Date

    Write-Host "Installing PostgreSQL $Version command line tools (psql)..." -ForegroundColor Yellow
    winget install --exact --id "PostgreSQL.PostgreSQL.$Version" `
        --accept-package-agreements --accept-source-agreements `
        --verbose-logs --log $wingetLog `
        --override '--mode unattended --unattendedmodeui none --disable-components server,pgAdmin,stackbuilder'
    $exitCode = $LASTEXITCODE

    $installerLogs = Get-ChildItem $env:TEMP -File -ErrorAction Ignore |
        Where-Object { $_.LastWriteTime -ge $startedAt -and $_.Name -match 'postgres|bitrock' }

    Write-Host ''
    Write-Host ('winget exit code: {0} (0x{1:X8})' -f $exitCode, $exitCode) -ForegroundColor ($exitCode -eq 0 ? 'Green' : 'Red')
    Write-Host "winget log:        $wingetLog"
    if ($installerLogs) {
        $installerLogs | ForEach-Object { Write-Host "installer log:     $($_.FullName)" }
    } else {
        Write-Host "installer log:     none found in $env:TEMP (the installer may not have started)"
    }

    if ($exitCode -ne 0) {
        return @{
            status  = 'error'
            message = ('winget exited with {0} (0x{0:X8}). Log: {1}' -f $exitCode, $wingetLog)
        }
    }
}

if (-not (Test-Path (Join-Path $pgBin 'psql.exe'))) {
    return @{ status = 'error'; message = "winget reported success but $pgBin\psql.exe does not exist." }
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not ($userPath -split ';' | Where-Object { $_ -eq $pgBin })) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$pgBin", 'User')
    Write-Host "Added $pgBin to user PATH" -ForegroundColor Green
}

$psqlVersion = & (Join-Path $pgBin 'psql.exe') --version
return @{ status = 'success'; message = $psqlVersion }
