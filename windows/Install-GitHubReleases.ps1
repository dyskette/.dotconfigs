#Requires -Version 7
<#
.SYNOPSIS
Installs or upgrades the tools listed in github-packages.jsonc from GitHub releases.

.DESCRIPTION
For each manifest entry the latest release (or the pinned "version" tag) is
compared with the record in ~/.local/opt/versions.json. A new release is
downloaded, verified against the release's published SHA256 when it has one,
extracted to staging and swapped into ~/.local/opt/<install_dir> atomically, so
a running program or a failed download never leaves a half-replaced install.
Binaries are linked into ~/.local/bin (copied when symlinks are not allowed).

Manifest entry:
  repo              owner/name
  asset_pattern     regex matching exactly one release asset
  bin               file name or list of names to put on PATH
  install_dir       folder under ~/.local/opt, also the version record key
  version           optional tag to pin instead of the latest release
  require_checksum  optional; true refuses a release without a published hash

Set GITHUB_TOKEN to raise the API rate limit.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Force,
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'github-packages.jsonc'),
    [string]$OptDirectory = (Join-Path $env:USERPROFILE '.local\opt'),
    [string]$BinDirectory = (Join-Path $env:USERPROFILE '.local\bin')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

<#
.SYNOPSIS
Extracts or copies a downloaded asset into a folder.
#>
function Expand-ReleaseAsset([string]$Path, [string]$Destination) {
    switch -Regex (Split-Path $Path -Leaf) {
        '\.(zip|tar\.gz|tgz|tar\.xz)$' { Expand-ArchiveChecked -ArchivePath $Path -DestinationPath $Destination }
        '\.exe$' {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
            Copy-Item -LiteralPath $Path -Destination $Destination
        }
        '\.msi$' {
            # Administrative install: unpacks the MSI's files without installing it.
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
            $arguments = '/a {0} /qn TARGETDIR={1}' -f (ConvertTo-CommandLineArgument $Path), (ConvertTo-CommandLineArgument $Destination)
            $exit = (Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru -NoNewWindow).ExitCode
            if ($exit -ne 0) { throw "msiexec /a exited with $exit." }
        }
        default { throw "Unsupported asset type: $(Split-Path $Path -Leaf)" }
    }
}

<#
.SYNOPSIS
Links each bin into the bin folder; returns the names that fell back to a copy.
#>
function Publish-Binary($Package, [string]$InstallPath, [string]$LinkDirectory) {
    foreach ($bin in @($Package.bin)) {
        $source = Join-Path $InstallPath $bin
        if (-not (Test-Path -LiteralPath $source)) {
            $source = (Get-ChildItem -LiteralPath $InstallPath -Recurse -File -Filter $bin | Select-Object -First 1)?.FullName
        }
        if (-not $source) { throw "binary $bin not found in the release" }
        if ((New-BinLink -Source $source -BinDirectory $LinkDirectory) -eq 'Copy') { $bin }
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    return New-StepResult Failed "Manifest not found: $ManifestPath"
}
$packages = @((Read-Jsonc $ManifestPath).packages)
if ($packages.Count -eq 0) {
    return New-StepResult Skipped 'The manifest lists no packages.'
}

$installed = [Collections.Generic.List[string]]::new()
$current = [Collections.Generic.List[string]]::new()
$failed = [Collections.Generic.List[string]]::new()
$copied = [Collections.Generic.List[string]]::new()

foreach ($package in $packages) {
    $name = $package.install_dir
    Write-Info "[$name] $($package.repo)"
    $workDir = $null
    try {
        $pin = $package.PSObject.Properties['version']?.Value
        $release = Get-GitHubRelease -Repository $package.repo -Tag $pin
        $tag = $release.tag_name
        $installPath = Join-Path $OptDirectory $name
        $record = Get-InstalledVersion -Name $name

        if (-not $Force -and $record -and $record.version -eq $tag -and (Test-Path -LiteralPath $installPath)) {
            Publish-Binary -Package $package -InstallPath $installPath -LinkDirectory $BinDirectory | ForEach-Object { $copied.Add($_) }
            $current.Add("$name $tag")
            continue
        }

        $assets = @($release.assets | Where-Object { $_.name -match $package.asset_pattern })
        if ($assets.Count -ne 1) {
            throw "asset_pattern '$($package.asset_pattern)' matches $($assets.Count) assets in $tag ($($assets.name -join ', '))"
        }
        $asset = $assets[0]
        if (-not $PSCmdlet.ShouldProcess($installPath, "Install $($package.repo) $tag ($($asset.name))")) { continue }

        $workDir = New-WorkDirectory -Prefix "dotconfigs-gh-$name"
        $hash = Get-ReleaseAssetHash -Release $release -AssetName $asset.name -WorkDirectory $workDir
        if (-not $hash) {
            if ($package.PSObject.Properties['require_checksum']?.Value) {
                throw "$tag publishes no checksum for $($asset.name) and require_checksum is set"
            }
            Write-Warning "[$name] $tag publishes no checksum for $($asset.name); installing it UNVERIFIED."
        }

        Write-Action "[$name] $($record ? "$($record.version) -> $tag" : "installing $tag")"
        $download = Invoke-Download -Uri $asset.browser_download_url -OutFile (Join-Path $workDir $asset.name) `
            -Headers (Get-GitHubHeader) -Sha256 $hash
        $extracted = Join-Path $workDir 'extracted'
        Expand-ReleaseAsset -Path $download -Destination $extracted

        # A single top-level folder is the package itself.
        $items = @(Get-ChildItem -LiteralPath $extracted -Force)
        $staging = if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $items[0].FullName } else { $extracted }
        Install-DirectoryAtomic -Source $staging -Destination $installPath

        Publish-Binary -Package $package -InstallPath $installPath -LinkDirectory $BinDirectory | ForEach-Object { $copied.Add($_) }
        Set-InstalledVersion -Name $name -Version $tag -Asset $asset.name `
            -Checksum ($hash ? "sha256:$hash" : '') -Verified ([bool]$hash)
        $installed.Add("$name $tag")
    } catch {
        Write-Warning "[$name] $($_.Exception.Message)"
        $failed.Add("$name ($($_.Exception.Message))")
    } finally {
        if ($workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue } # safe: private temp dir from New-WorkDirectory
    }
}

if ($copied.Count -gt 0) {
    Write-Warning "Copied instead of linked (needs Developer Mode or Administrator): $($copied -join ', ')."
}
$data = @{ Installed = $installed.ToArray(); UpToDate = $current.ToArray(); Failed = $failed.ToArray(); Copied = $copied.ToArray() }
if ($failed.Count -gt 0) {
    $status = if ($installed.Count + $current.Count -gt 0) { 'Partial' } else { 'Failed' }
    return New-StepResult $status "Failed: $($failed -join '; ')." -Data $data
}
if ($installed.Count -eq 0) {
    return New-StepResult Skipped "Up to date: $($current -join ', ')." -Data $data
}
return New-StepResult Success "Installed: $($installed -join ', ')." -Data $data
