#Requires -Version 7
<#
.SYNOPSIS
Installs the latest Node.js LTS with fnm and makes it the default.

.DESCRIPTION
Asks fnm for the newest LTS release, installs it when missing and points the
'default' alias at it. Nothing changes when that LTS is already the default.

Older Node versions are left installed: projects may pin them (.nvmrc).

No 'fnm env | Invoke-Expression' is needed: install, default and exec work
without the shell integration.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
    return New-StepResult Failed 'fnm is not on PATH (it is installed by the WingetPackages step).'
}

# "v26.13.1 (Lithium)"
$remote = (Invoke-Native -FilePath fnm -Arguments @('ls-remote', '--lts', '--latest') -Quiet).Output |
    Where-Object { $_ -match '^v\d+\.\d+\.\d+' } | Select-Object -Last 1
if (-not $remote) {
    return New-StepResult Failed 'fnm ls-remote did not return an LTS version.'
}
$latest = ($remote -split '\s+')[0]

# "* v26.13.0 default, lts-latest"
$installed = @((Invoke-Native -FilePath fnm -Arguments @('list') -Quiet).Output |
        Where-Object { $_ -match '^\*?\s*(v\d+\.\d+\.\d+)(.*)$' } |
        ForEach-Object { [pscustomobject]@{ Version = $Matches[1]; IsDefault = $Matches[2] -match '\bdefault\b' } })
$default = ($installed | Where-Object IsDefault | Select-Object -First 1)?.Version

if ($default -eq $latest) {
    return New-StepResult Skipped "Node.js $latest (latest LTS) is already the default." -Data @{ Version = $latest }
}

if ($latest -notin $installed.Version) {
    Write-Action "Installing Node.js $latest..."
    Invoke-Native -FilePath fnm -Arguments @('install', $latest) | Out-Null
}
Invoke-Native -FilePath fnm -Arguments @('default', $latest) -Quiet | Out-Null

$nodeVersion = ((Invoke-Native -FilePath fnm -Arguments @('exec', '--using=default', 'node', '--version') -Quiet).Output |
        Select-Object -First 1)
$from = if ($default) { " (was $default)" } else { '' }
return New-StepResult Success "Node.js $nodeVersion is the default$from." -Data @{ Version = $latest; Previous = $default }
