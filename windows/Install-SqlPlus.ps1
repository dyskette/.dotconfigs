#Requires -Version 7
<#
.SYNOPSIS
Installs or upgrades Oracle SQL*Plus from the Instant Client zips.

.DESCRIPTION
winget only carries Oracle.InstantClient.Basic, which has no sqlplus.exe;
Oracle publishes SQL*Plus as a separate Instant Client zip that needs Basic's
libraries next to it. Both are downloaded from Oracle's unversioned URLs (no
login needed), mirroring linux/tasks/bin/sqlplus.yml.

Oracle's URLs always point at the current release and publish no machine-readable
checksum, so updates are detected from the URLs' ETags (a HEAD request, no
download) and recorded in versions.json. A download is checked against the
advertised size, extracted to staging, and swapped into
~/.local/opt/oracle/instantclient_<version> atomically. Older instantclient_*
folders and their PATH entries are removed only after the new one is in place.

sqlplus.exe loads its DLLs from its own folder, so that folder goes on the user
PATH rather than being linked into ~/.local/bin.

.PARAMETER Force
Reinstall even when Oracle's files have not changed.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$OracleDirectory = (Join-Path $env:USERPROFILE '.local\opt\oracle'),
    [string]$BaseUrl = 'https://download.oracle.com/otn_software/nt/instantclient'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

$recordName = 'oracle-instantclient'
$packages = 'basic', 'sqlplus'

<#
.SYNOPSIS
HEAD each zip; returns url, size and a fingerprint (ETag, else Last-Modified + size).
#>
function Get-RemoteZip([string]$Base) {
    foreach ($package in $packages) {
        $url = "$Base/instantclient-$package-windows.zip"
        $response = Invoke-WebRequest -Method Head -Uri $url -UseBasicParsing
        $etag = "$($response.Headers['ETag'])"
        $size = [long]"$($response.Headers['Content-Length'])"
        $fingerprint = if ($etag) { $etag } else { "$($response.Headers['Last-Modified'])/$size" }
        [pscustomobject]@{ Package = $package; Url = $url; Size = $size; Fingerprint = $fingerprint }
    }
}

<#
.SYNOPSIS
Puts the client folder on the user PATH and drops entries for other versions.
#>
function Sync-ClientPath([string]$ClientPath) {
    $prefix = (Join-Path $OracleDirectory 'instantclient_').ToLowerInvariant()
    [void](Remove-PathEntry -Where {
            $entry = [Environment]::ExpandEnvironmentVariables($args[0]).TrimEnd('\').ToLowerInvariant()
            $entry.StartsWith($prefix) -and $entry -ne $ClientPath.TrimEnd('\').ToLowerInvariant()
        })
    [void](Add-PathEntry -Path $ClientPath)
}

<#
.SYNOPSIS
First line of 'sqlplus -version', e.g. "SQL*Plus: Release 23.0.0.0.0 - Production".
#>
function Get-SqlPlusVersion([string]$ClientPath) {
    (Invoke-Native -FilePath (Join-Path $ClientPath 'sqlplus.exe') -Arguments @('-version') -Quiet -NoThrow).Output |
        Where-Object { $_ } | Select-Object -First 1
}

try {
    $remote = @(Get-RemoteZip -Base $BaseUrl)
} catch {
    return New-StepResult Failed "Could not check Oracle for updates: $($_.Exception.Message)"
}
$fingerprint = ($remote.Fingerprint) -join '|'

$record = Get-InstalledVersion -Name $recordName
$installedPath = if ($record) { Join-Path $OracleDirectory $record.version } else { $null }
$isInstalled = $installedPath -and (Test-Path -LiteralPath (Join-Path $installedPath 'sqlplus.exe'))
if ($isInstalled -and -not $Force -and $record.PSObject.Properties['fingerprint'] -and $record.fingerprint -eq $fingerprint) {
    Sync-ClientPath $installedPath
    return New-StepResult Skipped "SQL*Plus is up to date ($($record.version))." -Data @{ Version = $record.version }
}

$workDir = New-WorkDirectory -Prefix 'dotconfigs-sqlplus'
try {
    $staging = Join-Path $workDir 'staging'
    foreach ($zip in $remote) {
        Write-Action "Downloading Instant Client $($zip.Package)..."
        $path = Invoke-Download -Uri $zip.Url -OutFile (Join-Path $workDir "instantclient-$($zip.Package)-windows.zip")
        $actualSize = (Get-Item -LiteralPath $path).Length
        if ($zip.Size -gt 0 -and $actualSize -ne $zip.Size) {
            return New-StepResult Failed "Instant Client $($zip.Package) is $actualSize bytes, Oracle advertised $($zip.Size)."
        }
        # Both zips share the same instantclient_<version> top folder.
        Expand-ArchiveChecked -ArchivePath $path -DestinationPath $staging
    }

    $client = @(Get-ChildItem -LiteralPath $staging -Directory -Filter 'instantclient_*')
    if ($client.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $client[0].FullName 'sqlplus.exe'))) {
        return New-StepResult Failed 'The Instant Client zips did not produce one instantclient_* folder with sqlplus.exe.'
    }
    $version = $client[0].Name
    $clientPath = Join-Path $OracleDirectory $version
    Install-DirectoryAtomic -Source $client[0].FullName -Destination $clientPath
} catch {
    return New-StepResult Failed "SQL*Plus was not installed: $($_.Exception.Message)"
} finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue # safe: private temp dir from New-WorkDirectory
}

Sync-ClientPath $clientPath

# Older releases go only now that the new one is in place; one still in use
# (an open sqlplus session) is left for a later run.
$leftOver = 0
foreach ($old in Get-ChildItem -LiteralPath $OracleDirectory -Directory -Filter 'instantclient_*' |
        Where-Object { $_.FullName -ne $clientPath }) {
    try {
        Remove-Item -LiteralPath $old.FullName -Recurse -Force # safe: an Instant Client folder this script installed
    } catch {
        $leftOver++
    }
}

Set-InstalledVersion -Name $recordName -Version $version -Asset 'instantclient-basic+sqlplus' -Extra @{ fingerprint = $fingerprint }

$message = "Installed $(Get-SqlPlusVersion $clientPath) in $clientPath."
if ($leftOver -gt 0) { $message += " $leftOver older folder(s) are in use and will be removed on a later run." }
$previous = if ($record) { $record.version } else { $null }
return New-StepResult Success $message -Data @{ Version = $version; Previous = $previous }
