#Requires -Version 7
<#
.SYNOPSIS
Installs Oracle SQL*Plus from the Instant Client Basic and SQL*Plus packages.

.DESCRIPTION
winget only carries Oracle.InstantClient.Basic, which has no sqlplus.exe, and
Oracle publishes SQL*Plus as a separate Instant Client package that needs
Basic's libraries next to it. Both zips are downloaded from Oracle (no OTN
login needed; the unversioned filenames always point at the current release)
and extracted into ~/.local/opt/oracle, mirroring linux/tasks/bin/sqlplus.yml.

sqlplus.exe loads its DLLs from its own folder, so that folder is added to the
user PATH rather than linked into ~/.local/bin.

Run by Install-WindowsEnvironment.ps1 through Invoke-Step, so it returns
@{ status; message } rather than exiting; it can also be run on its own.

.PARAMETER Force
Reinstall even if SQL*Plus is already present.

.OUTPUTS
Hashtable with status ("success" or "error") and message.

.EXAMPLE
./Install-SqlPlus.ps1
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$oracleDir = Join-Path $env:USERPROFILE '.local\opt\oracle'
$baseUrl = 'https://download.oracle.com/otn_software/nt/instantclient'
$packages = 'basic', 'sqlplus'

function Get-InstantClientDir {
    Get-ChildItem $oracleDir -Directory -Filter 'instantclient_*' -ErrorAction Ignore |
        Where-Object { Test-Path (Join-Path $_.FullName 'sqlplus.exe') } |
        Select-Object -First 1
}

$clientDir = Get-InstantClientDir
if ($clientDir -and -not $Force) {
    Write-Host "SQL*Plus already installed at $($clientDir.FullName). Skipping install." -ForegroundColor Green
} else {
    $downloadDir = Join-Path $env:TEMP "install-sqlplus-$(Get-Date -Format yyyyMMdd-HHmmss)"
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

    try {
        # Removed wholesale so a stale instantclient_* folder from an older
        # release cannot be picked up instead of the one extracted below.
        if (Test-Path $oracleDir) {
            Remove-Item $oracleDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $oracleDir -Force | Out-Null

        foreach ($package in $packages) {
            $zip = Join-Path $downloadDir "instantclient-$package-windows.zip"
            Write-Host "Downloading Instant Client $package..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri "$baseUrl/instantclient-$package-windows.zip" -OutFile $zip -UseBasicParsing
            # Both zips share the same instantclient_<version> top folder.
            Expand-Archive -Path $zip -DestinationPath $oracleDir -Force
        }
    } catch {
        return @{ status = 'error'; message = "Download or extraction failed: $($_.Exception.Message)" }
    } finally {
        Remove-Item $downloadDir -Recurse -Force -ErrorAction Ignore
    }

    $clientDir = Get-InstantClientDir
    if (-not $clientDir) {
        return @{ status = 'error'; message = "sqlplus.exe not found under $oracleDir after extraction." }
    }
}

$clientPath = $clientDir.FullName
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
# Drop entries for older Instant Client releases left by a previous install.
$entries = $userPath -split ';' | Where-Object {
    $_ -and -not ($_ -like "$oracleDir\instantclient_*" -and $_ -ne $clientPath)
}
if ($entries -notcontains $clientPath) {
    $entries += $clientPath
    Write-Host "Added $clientPath to user PATH" -ForegroundColor Green
}
[Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')

$sqlplusVersion = & (Join-Path $clientPath 'sqlplus.exe') -version | Where-Object { $_ } | Select-Object -First 1
return @{ status = 'success'; message = $sqlplusVersion }
