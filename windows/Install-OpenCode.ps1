#Requires -Version 7
<#
.SYNOPSIS
Installs or upgrades the standalone OpenCode CLI (v2) in ~/.local/opt/opencode.

.DESCRIPTION
OpenCode 2 has no winget package and the sst/opencode GitHub releases still
carry the v1 line, so the release comes from OpenCode's update API, which lists
the current version and a SHA256 per asset. The download is verified, staged,
and swapped in atomically: a running opencode.exe makes the swap fail cleanly
and leaves the old install working. opencode.exe is then linked into
~/.local/bin (on PATH via the Dotfiles step), mirroring linux/tasks/bin/opencode.yml.

The npm/bun packages are avoided on purpose: they install under the active fnm
Node version and disappear when the default Node changes.

.PARAMETER Force
Reinstall even when the installed version matches.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$ManifestUrl = 'https://opencode.ai/update/api/latest/cli/opencode',
    [string]$InstallDirectory = (Join-Path $env:USERPROFILE '.local\opt\opencode'),
    [string]$BinDirectory = (Join-Path $env:USERPROFILE '.local\bin')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

$binaryPath = Join-Path $InstallDirectory 'opencode.exe'
# The API also publishes -baseline variants for CPUs without AVX2.
$assetName = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'opencode-windows-arm64.zip' } else { 'opencode-windows-x64.zip' }

<#
.SYNOPSIS
Version reported by an opencode.exe ("opencode v2.2.6" -> "2.2.6"), or $null.
#>
function Get-OpenCodeVersion([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $output = (Invoke-Native -FilePath $Path -Arguments @('--version') -Quiet -NoThrow).Output | Select-Object -First 1
    if ("$output" -match '\d+\.\d+\.\d+') { return $Matches[0] }
    return $null
}

<#
.SYNOPSIS
Links opencode.exe into the bin folder unless an up-to-date link or copy is there.
#>
function Update-OpenCodeLink {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Internal helper of a step script; the step itself is the unit of change.')]
    param()

    # New-BinLink leaves an up-to-date link or identical copy alone.
    $kind = New-BinLink -Source $binaryPath -BinDirectory $BinDirectory
    if ($kind -eq 'Unchanged') { return $null }
    if ($kind -eq 'Copy') {
        Write-Warning "Copied opencode.exe into ${BinDirectory}: creating a symlink needs Developer Mode or Administrator."
    }
    return $kind
}

try {
    $manifest = Invoke-RestMethod -Uri $ManifestUrl
} catch {
    return New-StepResult Failed "Could not read $ManifestUrl : $($_.Exception.Message)"
}
$latest = [string]$manifest.version
$file = $manifest.metadata.files.PSObject.Properties[$assetName]?.Value
if (-not $file) {
    return New-StepResult Failed "OpenCode $latest publishes no asset named $assetName."
}

$installed = Get-OpenCodeVersion $binaryPath
if ($installed -eq $latest -and -not $Force) {
    $linked = Update-OpenCodeLink
    $note = if ($linked) { " Re-linked into $BinDirectory ($linked)." } else { '' }
    # An earlier upgrade may have left the old version behind while it ran.
    $removed = @(Get-ChildItem -LiteralPath (Split-Path $InstallDirectory -Parent) -Directory -Filter "$(Split-Path $InstallDirectory -Leaf).old-*" -ErrorAction SilentlyContinue)
    $busy = @(Remove-InstallLeftover -Destination $InstallDirectory)
    if ($removed.Count -gt $busy.Count) { $note += " Removed $($removed.Count - $busy.Count) leftover old install(s)." }
    return New-StepResult Skipped "OpenCode $latest is already installed.$note" -Data @{ Version = $latest }
}

Write-Action ($installed ? "Upgrading OpenCode $installed -> $latest..." : "Installing OpenCode $latest...")
$workDir = New-WorkDirectory -Prefix 'dotconfigs-opencode'
try {
    $zip = Invoke-Download -Uri $file.url -OutFile (Join-Path $workDir $assetName) -Sha256 $file.sha256
    $staging = Join-Path $workDir 'staging'
    Expand-ArchiveChecked -ArchivePath $zip -DestinationPath $staging
    if (-not (Test-Path -LiteralPath (Join-Path $staging 'opencode.exe'))) {
        return New-StepResult Failed "opencode.exe is not at the root of $assetName."
    }
    Install-DirectoryAtomic -Source $staging -Destination $InstallDirectory
} catch {
    return New-StepResult Failed "OpenCode $latest was not installed: $($_.Exception.Message)"
} finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue # safe: private temp dir from New-WorkDirectory
}

Update-OpenCodeLink | Out-Null
$now = Get-OpenCodeVersion $binaryPath
if ($now -ne $latest) {
    return New-StepResult Failed "Installed OpenCode reports '$now', expected $latest."
}
return New-StepResult Success "OpenCode $latest installed$($installed ? " (was $installed)" : '')." -Data @{ Version = $latest; Previous = $installed }
