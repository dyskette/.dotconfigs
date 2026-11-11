#Requires -Version 7
<#
.SYNOPSIS
Installs or upgrades JetBrains Mono NL Nerd Font for the current user.

.DESCRIPTION
Downloads the font archive from the latest nerd-fonts release, verifies it
against the release's SHA-256.txt, and installs the matching .ttf files as
per-user fonts (no Administrator needed).

Installed files carry the release tag in their name, e.g.
JetBrainsMonoNLNerdFont-Regular_v3.5.1.ttf. An upgrade therefore never
overwrites a file a running program (the terminal, typically) has loaded: the
new files are added, the registry entries are pointed at them, and the old
files are deleted when nothing holds them. Old files still in use are retried
on the next run.

.PARAMETER Repository
GitHub repository publishing the font.

.PARAMETER Archive
Release asset holding the fonts.

.PARAMETER FontPrefix
File name prefix of the font files to install, e.g. 'JetBrainsMonoNLNerdFont-'.

.PARAMETER FontDirectory
Per-user font folder.

.PARAMETER RegistryPath
Per-user font registration key. A parameter so tests can use a scratch key.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param(
    [string]$Repository = 'ryanoasis/nerd-fonts',
    [string]$Archive = 'JetBrainsMono.zip',
    [string]$FontPrefix = 'JetBrainsMonoNLNerdFont-',
    [string]$FontDirectory = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'),
    [string]$RegistryPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

$registryPath = $RegistryPath
$recordName = "font:$FontPrefix"

<#
.SYNOPSIS
Registry values (name -> file path) for the fonts with this prefix.
#>
function Get-RegisteredFont {
    $key = Get-Item -Path $registryPath -ErrorAction SilentlyContinue
    $fonts = @{}
    if ($key) {
        foreach ($name in $key.GetValueNames() | Where-Object { $_ -like "$FontPrefix* (TrueType)" }) {
            $fonts[$name] = [string]$key.GetValue($name)
        }
    }
    return $fonts
}

$release = Get-GitHubRelease -Repository $Repository
$tag = $release.tag_name
$asset = @($release.assets | Where-Object name -eq $Archive)
if ($asset.Count -ne 1) {
    return New-StepResult Failed "Release $tag of $Repository has no asset named $Archive."
}

$record = Get-InstalledVersion -Name $recordName
$registered = Get-RegisteredFont
$allPresent = $registered.Count -gt 0 -and
    @($registered.Values | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -eq 0
if ($record -and $record.version -eq $tag -and $allPresent) {
    return New-StepResult Skipped "$FontPrefix* $tag is already installed ($($registered.Count) files)." -Data @{ Version = $tag }
}

$workDir = New-WorkDirectory -Prefix 'dotconfigs-font'
try {
    $hash = Get-ReleaseAssetHash -Release $release -AssetName $Archive -WorkDirectory $workDir
    if (-not $hash) { Write-Warning "$Repository $tag publishes no checksum for $Archive; installing it UNVERIFIED." }

    Write-Action "Downloading $Archive ($tag)..."
    $archivePath = Invoke-Download -Uri $asset[0].browser_download_url -OutFile (Join-Path $workDir $Archive) -Sha256 $hash
    $extracted = Join-Path $workDir 'extracted'
    Expand-ArchiveChecked -ArchivePath $archivePath -DestinationPath $extracted

    $sources = @(Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter "$FontPrefix*.ttf")
    if ($sources.Count -eq 0) {
        return New-StepResult Failed "$Archive contains no $FontPrefix*.ttf files."
    }

    New-Item -ItemType Directory -Path $FontDirectory -Force | Out-Null
    if (-not (Test-Path -Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }

    $wanted = @{}
    foreach ($source in $sources) {
        $target = Join-Path $FontDirectory ('{0}_{1}{2}' -f $source.BaseName, $tag, $source.Extension)
        Copy-Item -LiteralPath $source.FullName -Destination $target -Force
        $valueName = "$($source.BaseName) (TrueType)"
        Set-ItemProperty -Path $registryPath -Name $valueName -Value $target -Type String
        $wanted[$valueName] = $target
    }
} finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue # safe: private temp dir from New-WorkDirectory
}

# Styles dropped by the new release lose their registry entry.
foreach ($stale in @((Get-RegisteredFont).Keys | Where-Object { -not $wanted.ContainsKey($_) })) {
    Remove-ItemProperty -Path $registryPath -Name $stale
}

# Files no longer referenced: earlier versions, and the unversioned names the
# original script used. A file a running program holds is left for next time.
$inUse = 0
$keep = @($wanted.Values)
foreach ($old in Get-ChildItem -LiteralPath $FontDirectory -File -Filter "$FontPrefix*.ttf" |
        Where-Object { $_.FullName -notin $keep }) {
    try { Remove-Item -LiteralPath $old.FullName -Force } catch { $inUse++ }
}

$broadcast = Send-BroadcastMessage -Message 0x1D   # WM_FONTCHANGE
Set-InstalledVersion -Name $recordName -Version $tag -Asset $Archive `
    -Checksum ($hash ? "sha256:$hash" : '') -Verified ([bool]$hash)

$message = "Installed $($wanted.Count) $FontPrefix* files ($tag)."
if ($inUse -gt 0) { $message += " $inUse old file(s) are in use and will be removed on a later run." }
if (-not $broadcast) { $message += ' Running apps may need a restart to see the new fonts.' }
$from = if ($record) { $record.version } else { $null }
return New-StepResult Success $message -Data @{ Version = $tag; Previous = $from; Verified = [bool]$hash; OldFilesInUse = $inUse }
