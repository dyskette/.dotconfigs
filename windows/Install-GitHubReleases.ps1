#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Installs tools from GitHub releases to ~/.local/opt/

.DESCRIPTION
    Reads a github-packages.jsonc manifest and installs the latest GitHub releases
    for each declared package. Tracks installed versions in ~/.local/opt/versions.json
    and only downloads when a new version is available. Binaries are symlinked into
    ~/.local/bin/ for PATH access.

.NOTES
    Requirements:
    - Internet connection
    - Optional: GITHUB_TOKEN environment variable for higher API rate limits
    - ~/.local/bin must be in PATH (Configure-Dotfiles.ps1 handles this)
#>

param(
    [Parameter(HelpMessage="Show what would be updated without making changes")]
    [switch]$DryRun,

    [Parameter(HelpMessage="Reinstall even if the installed version matches the latest")]
    [switch]$Force,

    [Parameter(HelpMessage="Path to the manifest file (defaults to github-packages.jsonc in script directory)")]
    [string]$ManifestPath
)

$ErrorActionPreference = "Stop"

# ── Constants ──────────────────────────────────────────────────────────────

$LocalOpt = Join-Path $env:USERPROFILE ".local\opt"
$LocalBin = Join-Path $env:USERPROFILE ".local\bin"
$VersionsFile = Join-Path $LocalOpt "versions.json"
$ETagCacheFile = Join-Path $LocalOpt ".etag-cache.json"
$GitHubApiBase = "https://api.github.com/repos"

if (-not $ManifestPath) {
    $ManifestPath = Join-Path $PSScriptRoot "github-packages.jsonc"
}

# ── Helpers ────────────────────────────────────────────────────────────────

function Read-Jsonc {
    param([string]$Path)
    $raw = Get-Content $Path -Raw
    $json = $raw -replace '(?m)^\s*//.*$', '' -replace '(?<=,|\{|\[)\s*//.*$', ''
    return $json | ConvertFrom-Json
}

function Get-Versions {
    if (Test-Path $VersionsFile) {
        $content = Get-Content $VersionsFile -Raw
        if ($content.Trim()) {
            return $content | ConvertFrom-Json
        }
    }
    return [PSCustomObject]@{}
}

function Save-Versions {
    param([PSCustomObject]$Versions)
    $tempPath = "$VersionsFile.tmp"
    $Versions | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding utf8
    Move-Item -Path $tempPath -Destination $VersionsFile -Force
}

function Get-GitHubHeaders {
    param([string]$ETag)
    $headers = @{
        "Accept"     = "application/vnd.github+json"
        "User-Agent" = "dotconfigs-installer/1.0"
    }
    if ($env:GITHUB_TOKEN) {
        $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
    }
    if ($ETag) {
        $headers["If-None-Match"] = $ETag
    }
    return $headers
}

function Get-ETagCache {
    if (Test-Path $ETagCacheFile) {
        $content = Get-Content $ETagCacheFile -Raw
        if ($content.Trim()) {
            return $content | ConvertFrom-Json
        }
    }
    return [PSCustomObject]@{}
}

function Save-ETagCache {
    param([PSCustomObject]$Cache)
    $tempPath = "$ETagCacheFile.tmp"
    $Cache | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $tempPath -Encoding utf8
    Move-Item -Path $tempPath -Destination $ETagCacheFile -Force
}

function Get-LatestRelease {
    param([string]$Repo)

    $etagCache = Get-ETagCache
    $cachedETag = $null
    if ($etagCache.PSObject.Properties[$Repo]) {
        $cachedETag = $etagCache.$Repo.etag
    }

    $url = "$GitHubApiBase/$Repo/releases/latest"
    $headers = Get-GitHubHeaders -ETag $cachedETag

    try {
        $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing
        $release = $response.Content | ConvertFrom-Json

        $newETag = $response.Headers["ETag"]
        if ($newETag) {
            $etagCache | Add-Member -NotePropertyName $Repo -NotePropertyValue ([PSCustomObject]@{
                etag = if ($newETag -is [array]) { $newETag[0] } else { $newETag }
                data = $release
            }) -Force
            Save-ETagCache -Cache $etagCache
        }

        return $release
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 304) {
            Write-Host "    Using cached release info" -ForegroundColor Gray
            return $etagCache.$Repo.data
        }
        if ($_.Exception.Response.StatusCode.value__ -eq 403) {
            $resetHeader = $_.Exception.Response.Headers["X-RateLimit-Reset"]
            if ($resetHeader) {
                $resetValue = if ($resetHeader -is [array]) { $resetHeader[0] } else { $resetHeader }
                $resetTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$resetValue).LocalDateTime
                Write-Warning "    GitHub API rate limited. Resets at $resetTime"
                Write-Warning "    Set GITHUB_TOKEN environment variable to increase limits."
            }
        }
        throw
    }
}

function Find-Asset {
    param(
        [object]$Release,
        [string]$Pattern
    )
    $matched = $Release.assets | Where-Object { $_.name -match $Pattern }
    if ($matched -is [array]) {
        return $matched[0]
    }
    return $matched
}

function Find-ChecksumAsset {
    param([object]$Release)
    return $Release.assets | Where-Object {
        $_.name -match '(?i)(checksums?|sha256sums?|SHA256SUMS)(\.txt)?$'
    } | Select-Object -First 1
}

function Test-AssetChecksum {
    param(
        [string]$FilePath,
        [string]$FileName,
        [object]$ChecksumAsset
    )
    $checksumFile = Join-Path ([System.IO.Path]::GetTempPath()) "gh-checksums.txt"
    try {
        $headers = Get-GitHubHeaders
        Invoke-WebRequest -Uri $ChecksumAsset.browser_download_url -Headers $headers `
            -OutFile $checksumFile -UseBasicParsing
        $lines = Get-Content $checksumFile
        $match = $lines | Where-Object { $_ -match [regex]::Escape($FileName) }
        if ($match) {
            $expectedHash = ($match -split '\s+')[0]
            $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLower()
            if ($actualHash -eq $expectedHash.ToLower()) {
                return @{ verified = $true; hash = "sha256:$actualHash" }
            } else {
                return @{ verified = $false; expected = $expectedHash; actual = $actualHash }
            }
        }
        return @{ verified = $null; message = "No checksum entry found for $FileName" }
    } finally {
        Remove-Item -Path $checksumFile -Force -ErrorAction SilentlyContinue
    }
}

function Expand-Asset {
    param(
        [string]$ArchivePath,
        [string]$DestinationPath
    )
    $name = [System.IO.Path]::GetFileName($ArchivePath)

    if ($name -match '\.zip$') {
        Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
    } elseif ($name -match '\.(tar\.gz|tgz)$') {
        tar -xzf $ArchivePath -C $DestinationPath
    } elseif ($name -match '\.tar\.xz$') {
        tar -xf $ArchivePath -C $DestinationPath
    } elseif ($name -match '\.exe$') {
        Copy-Item -Path $ArchivePath -Destination $DestinationPath -Force
    } elseif ($name -match '\.msi$') {
        Start-Process msiexec -ArgumentList "/a `"$ArchivePath`" /qn TARGETDIR=`"$DestinationPath`"" -Wait -NoNewWindow
    } else {
        throw "Unsupported archive format: $name"
    }
}

function New-BinLink {
    param(
        [string]$Source,
        [string]$LinkName
    )
    $linkPath = Join-Path $LocalBin $LinkName
    if (Test-Path $linkPath) {
        Remove-Item -Path $linkPath -Force
    }
    try {
        New-Item -Path $linkPath -ItemType SymbolicLink -Target $Source -Force | Out-Null
    } catch {
        Write-Host "    Symlink failed, falling back to copy" -ForegroundColor Gray
        Copy-Item -Path $Source -Destination $linkPath -Force
    }
}

# ── Main ───────────────────────────────────────────────────────────────────

Write-Host "=== GitHub Release Packages ===" -ForegroundColor Cyan

if (-not (Test-Path $ManifestPath)) {
    Write-Warning "Manifest not found: $ManifestPath"
    return @{ status = "error"; message = "Manifest file not found" }
}

foreach ($dir in @($LocalOpt, $LocalBin)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

$manifest = Read-Jsonc -Path $ManifestPath
$versions = Get-Versions

if (-not $manifest.packages -or $manifest.packages.Count -eq 0) {
    Write-Host "No packages defined in manifest." -ForegroundColor Yellow
    return @{ status = "success"; message = "No packages to install" }
}

Write-Host "Found $($manifest.packages.Count) package(s) in manifest" -ForegroundColor Gray

if ($DryRun) {
    Write-Host "[DRY RUN] No changes will be made" -ForegroundColor Cyan
}

$installed = 0
$skipped = 0
$failed = 0
$failedPackages = @()

foreach ($pkg in $manifest.packages) {
    Write-Host ""
    Write-Host "  [$($pkg.install_dir)] Checking $($pkg.repo)..." -ForegroundColor Yellow

    $tempDir = $null

    try {
        # Query GitHub API
        $release = Get-LatestRelease -Repo $pkg.repo
        $latestVersion = $release.tag_name
        Write-Host "    Latest: $latestVersion" -ForegroundColor Gray

        # Compare with installed version
        $currentVersion = $null
        if ($versions.PSObject.Properties[$pkg.install_dir]) {
            $currentVersion = $versions.$($pkg.install_dir).version
        }

        if ($currentVersion -eq $latestVersion -and -not $Force) {
            Write-Host "    Already up to date ($currentVersion)" -ForegroundColor Green
            $skipped++
            continue
        }

        if ($currentVersion) {
            Write-Host "    Updating: $currentVersion -> $latestVersion" -ForegroundColor Yellow
        } else {
            Write-Host "    Installing: $latestVersion" -ForegroundColor Yellow
        }

        # Find matching asset
        $asset = Find-Asset -Release $release -Pattern $pkg.asset_pattern
        if (-not $asset) {
            throw "No asset matching pattern '$($pkg.asset_pattern)' in release $latestVersion"
        }
        Write-Host "    Asset: $($asset.name)" -ForegroundColor Gray

        if ($DryRun) {
            Write-Host "    [DRY RUN] Would install $($asset.name)" -ForegroundColor Cyan
            $installed++
            continue
        }

        # Download
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "gh-install-$($pkg.install_dir)"
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        $downloadPath = Join-Path $tempDir $asset.name
        $dlHeaders = Get-GitHubHeaders
        Write-Host "    Downloading..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $asset.browser_download_url -Headers $dlHeaders `
            -OutFile $downloadPath -UseBasicParsing

        # Checksum verification
        $checksumResult = $null
        $checksumAsset = Find-ChecksumAsset -Release $release
        if ($checksumAsset) {
            Write-Host "    Verifying checksum..." -ForegroundColor Yellow
            $checksumResult = Test-AssetChecksum -FilePath $downloadPath `
                -FileName $asset.name -ChecksumAsset $checksumAsset
            if ($checksumResult.verified -eq $false) {
                throw "Checksum mismatch for $($asset.name): expected $($checksumResult.expected), got $($checksumResult.actual)"
            }
            if ($checksumResult.verified -eq $true) {
                Write-Host "    Checksum verified" -ForegroundColor Green
            } else {
                Write-Host "    $($checksumResult.message)" -ForegroundColor Gray
            }
        }

        # Extract
        $extractDir = Join-Path $tempDir "extracted"
        New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
        Write-Host "    Extracting..." -ForegroundColor Yellow
        Expand-Asset -ArchivePath $downloadPath -DestinationPath $extractDir

        # Unwrap single nested directory
        $extractedItems = Get-ChildItem -Path $extractDir
        $sourceDir = $extractDir
        if ($extractedItems.Count -eq 1 -and $extractedItems[0].PSIsContainer) {
            $sourceDir = $extractedItems[0].FullName
        }

        # Install to ~/.local/opt/
        $installPath = Join-Path $LocalOpt $pkg.install_dir
        if (Test-Path $installPath) {
            Remove-Item -Path $installPath -Recurse -Force
        }
        Copy-Item -Path $sourceDir -Destination $installPath -Recurse -Force

        # Create bin links
        $binEntries = if ($pkg.bin -is [array]) { $pkg.bin } else { @($pkg.bin) }
        foreach ($bin in $binEntries) {
            $binSource = Join-Path $installPath $bin
            if (-not (Test-Path $binSource)) {
                $found = Get-ChildItem -Path $installPath -Filter $bin -Recurse | Select-Object -First 1
                if ($found) {
                    $binSource = $found.FullName
                } else {
                    Write-Warning "    Binary not found: $bin"
                    continue
                }
            }
            New-BinLink -Source $binSource -LinkName $bin
            Write-Host "    Linked: $bin" -ForegroundColor Green
        }

        # Record checksum
        $recordedChecksum = ""
        if ($checksumResult -and $checksumResult.hash) {
            $recordedChecksum = $checksumResult.hash
        } else {
            $hash = (Get-FileHash -Path $downloadPath -Algorithm SHA256).Hash.ToLower()
            $recordedChecksum = "sha256:$hash"
        }

        # Update versions.json
        $versionEntry = [PSCustomObject]@{
            version      = $latestVersion
            installed_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            asset        = $asset.name
            checksum     = $recordedChecksum
        }
        $versions | Add-Member -NotePropertyName $pkg.install_dir -NotePropertyValue $versionEntry -Force
        Save-Versions -Versions $versions

        Write-Host "    Installed $latestVersion" -ForegroundColor Green
        $installed++

    } catch {
        Write-Warning "    Failed: $_"
        $failed++
        $failedPackages += $pkg.install_dir
    } finally {
        if ($tempDir -and (Test-Path $tempDir)) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ── Summary ────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "GitHub Release Packages Summary:" -ForegroundColor Cyan
$actionWord = if ($DryRun) { "Would install" } else { "Installed" }
Write-Host "  ${actionWord}: $installed" -ForegroundColor Green
Write-Host "  Up to date: $skipped" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

if ($failedPackages.Count -gt 0) {
    $failedPackages | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
}

$status = if ($failed -eq 0) { "success" } elseif ($installed -gt 0) { "partial" } else { "error" }

return @{
    status          = $status
    message         = "$actionWord $installed package(s), $skipped up to date, $failed failed"
    installed       = $installed
    skipped         = $skipped
    failed          = $failed
    failed_packages = $failedPackages
}
