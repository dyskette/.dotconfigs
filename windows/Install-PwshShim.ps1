#Requires -Version 7
<#
.SYNOPSIS
Builds the pwsh.exe shim (windows/pwsh-shim) and installs it in
~/.local/opt/pwsh-shim.

.DESCRIPTION
psmux 3.4.0 starts every popup command as pwsh -NoProfile -Command <cmd>,
about 400 ms of PowerShell startup before anything shows. The shim, first on
PATH, starts a command that is a plain program call (& 'fzf' ...) directly
instead, in about 2 ms, and hands anything else to the real pwsh. See
windows/pwsh-shim/src/main.rs.

The PowerShell profile puts the install folder first on PATH, so psmux
servers started from a shell find this pwsh first. Not ~/.local/bin: that
folder is on PATH everywhere, and nothing but the shell needs the shim.

The build goes to a folder kept between runs, so a rerun only relinks when
the source changed. A shim that is running (an open popup) cannot be
overwritten, only renamed, so the old one is moved aside first and removed
on a later run.

.PARAMETER InstallDirectory
Where pwsh.exe goes.

.PARAMETER TargetDirectory
cargo's build folder.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param(
    [string]$InstallDirectory = (Join-Path $env:USERPROFILE '.local\opt\pwsh-shim'),
    [string]$TargetDirectory = (Join-Path $env:LOCALAPPDATA 'dotconfigs\pwsh-shim-target'),
    [string]$SourceDirectory = (Join-Path $PSScriptRoot 'pwsh-shim')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

if (-not (Get-Command cargo -CommandType Application -ErrorAction SilentlyContinue)) {
    return New-StepResult Failed 'cargo is not on PATH; install Rust (rustup) and run this step again.'
}

Write-Action 'Building the pwsh shim...'
try {
    Invoke-Native -FilePath cargo -Quiet -Arguments @(
        'build', '--release', '--quiet',
        '--manifest-path', (Join-Path $SourceDirectory 'Cargo.toml'),
        '--target-dir', $TargetDirectory
    ) | Out-Null
} catch {
    return New-StepResult Failed "The pwsh shim did not build: $($_.Exception.Message)"
}

$built = Join-Path $TargetDirectory 'release\pwsh.exe'
$installed = Join-Path $InstallDirectory 'pwsh.exe'
if (-not (Test-Path -LiteralPath $built)) {
    return New-StepResult Failed "cargo reported success but $built is missing."
}

# Shims moved aside by earlier runs, once nothing runs them any more.
Get-ChildItem -LiteralPath $InstallDirectory -Filter 'pwsh.exe.old-*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue # safe: only old copies of the shim, in its own folder

if ((Test-Path -LiteralPath $installed) -and
    (Get-FileHash -LiteralPath $built).Hash -eq (Get-FileHash -LiteralPath $installed).Hash) {
    return New-StepResult Skipped "The pwsh shim in $InstallDirectory is up to date."
}

New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
if (Test-Path -LiteralPath $installed) {
    Move-Item -LiteralPath $installed -Destination "$installed.old-$([DateTime]::Now.ToString('yyyyMMddHHmmss'))"
}
Copy-Item -LiteralPath $built -Destination $installed
return New-StepResult Success "pwsh shim installed in $InstallDirectory."
