#Requires -Version 7
<#
.SYNOPSIS
Makes sure winget works, and updates it from its GitHub release.

.DESCRIPTION
Later steps depend on winget, so this step is Critical. To keep a GitHub rate
limit or a network problem from stopping a machine whose winget already works:

- winget works: its version is compared with the latest microsoft/winget-cli
  release. When the check or the update fails, the step reports Partial, which
  shows in the summary but does not stop the run.
- winget is missing or broken (it cannot list its sources): the latest release
  is installed, and any failure fails the step.

Installing means: the release's dependency packages (VCLibs, UI.Xaml) first,
otherwise winget registers but fails to open its sources (0x8A15000F), then the
.msixbundle, verified against the release checksum when one is published.

.PARAMETER Force
Reinstall even when the installed version is current.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$Repository = 'microsoft/winget-cli'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

<#
.SYNOPSIS
Installed winget version, or $null when winget is missing or cannot list its sources.
#>
function Get-WorkingWingetVersion {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $null }
    $version = Invoke-Native -FilePath winget -Arguments @('--version') -Quiet -NoThrow
    if (-not $version.Succeeded) { return $null }
    $sources = Invoke-Native -FilePath winget -Arguments @('source', 'list') -Quiet -NoThrow
    if (-not $sources.Succeeded) { return $null }
    return ConvertTo-WingetVersion ($version.Output | Select-Object -First 1)
}

<#
.SYNOPSIS
"v1.29.380" -> [version] 1.29.380, or $null.
#>
function ConvertTo-WingetVersion([string]$Text) {
    if ("$Text" -match '(\d+\.\d+(\.\d+)?)') { return [version]$Matches[1] }
    return $null
}

<#
.SYNOPSIS
Installs the release's dependencies and .msixbundle.
#>
function Install-WingetRelease($Release) {
    $bundle = @($Release.assets | Where-Object { $_.name -like '*.msixbundle' })
    if ($bundle.Count -ne 1) { throw "Expected one .msixbundle in winget $($Release.tag_name), found $($bundle.Count)." }

    $workDir = New-WorkDirectory -Prefix 'dotconfigs-winget'
    try {
        $deps = $Release.assets | Where-Object { $_.name -like '*Dependencies.zip' } | Select-Object -First 1
        if ($deps) {
            $depsZip = Invoke-Download -Uri $deps.browser_download_url -OutFile (Join-Path $workDir $deps.name) `
                -Sha256 (Get-ReleaseAssetHash -Release $Release -AssetName $deps.name -WorkDirectory $workDir)
            Expand-ArchiveChecked -ArchivePath $depsZip -DestinationPath (Join-Path $workDir 'deps')
            $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
            foreach ($package in Get-ChildItem (Join-Path $workDir 'deps') -Recurse -Filter '*.appx' |
                    Where-Object { $_.FullName -like "*\$arch\*" }) {
                Write-Info "Installing dependency $($package.Name)"
                # A dependency that is already present at an equal or newer
                # version fails to install; winget still works in that case.
                try { Add-AppxPackage -Path $package.FullName } catch { Write-Info "  skipped: $($_.Exception.Message)" }
            }
        } else {
            Write-Warning "winget $($Release.tag_name) publishes no dependency bundle; winget may fail to open its sources."
        }

        $hash = Get-ReleaseAssetHash -Release $Release -AssetName $bundle[0].name -WorkDirectory $workDir
        if (-not $hash) { Write-Warning "winget $($Release.tag_name) publishes no checksum for $($bundle[0].name); installing it UNVERIFIED." }
        $bundlePath = Invoke-Download -Uri $bundle[0].browser_download_url -OutFile (Join-Path $workDir $bundle[0].name) -Sha256 $hash
        Write-Action "Installing winget $($Release.tag_name)..."
        Add-AppxPackage -Path $bundlePath
    } finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue # safe: private temp dir from New-WorkDirectory
    }
    Update-SessionPath
}

$installed = Get-WorkingWingetVersion

try {
    $release = Get-GitHubRelease -Repository $Repository
    $latest = ConvertTo-WingetVersion $release.tag_name
} catch {
    if ($installed) {
        return New-StepResult Partial "winget $installed works, but checking for an update failed: $($_.Exception.Message)" -Data @{ Version = "$installed" }
    }
    return New-StepResult Failed "winget is missing or broken, and its release could not be fetched: $($_.Exception.Message)"
}

if ($installed -and $latest -and $installed -ge $latest -and -not $Force) {
    return New-StepResult Skipped "winget $installed is up to date." -Data @{ Version = "$installed" }
}

try {
    Install-WingetRelease $release
} catch {
    if ($installed) {
        return New-StepResult Partial "winget $installed works, but updating to $latest failed: $($_.Exception.Message)" -Data @{ Version = "$installed" }
    }
    return New-StepResult Failed "Installing winget $latest failed: $($_.Exception.Message)"
}

$now = Get-WorkingWingetVersion
if (-not $now) {
    return New-StepResult Failed "winget $latest was installed but cannot list its sources (try 'winget source reset --force')."
}
$from = if ($installed) { " (was $installed)" } else { '' }
return New-StepResult Success "winget $now is ready$from." -Data @{ Version = "$now"; Previous = "$installed" }
