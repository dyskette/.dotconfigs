#Requires -Version 7
<#
.SYNOPSIS
Installs the standalone OpenCode CLI (v2) into ~/.local/opt/opencode.

.DESCRIPTION
OpenCode 2 has no winget package ("Windows package managers are not supported"
per the docs) and the sst/opencode GitHub releases still carry the v1 line, so
Install-GitHubReleases.ps1 cannot reach it either. Its update API lists the
current version plus a sha256 per asset, so this script resolves the release,
skips the download when the installed binary already matches, verifies the hash
and links opencode.exe into ~/.local/bin (put on PATH by Configure-Dotfiles.ps1),
mirroring linux/tasks/bin/opencode.yml.

The npm/bun packages (@opencode/cli) are deliberately avoided: they install the
binary under the active fnm Node version, so it disappears when the default
Node changes.

Run by Install-WindowsEnvironment.ps1 through Invoke-Step, so it returns
@{ status; message } rather than exiting; it can also be run on its own.

.PARAMETER Force
Reinstall even when the installed version already matches the manifest.

.OUTPUTS
Hashtable with status ("success" or "error") and message.

.EXAMPLE
./Install-OpenCode.ps1
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$manifestUrl = 'https://opencode.ai/update/api/latest/cli/opencode'
$installDir = Join-Path $env:USERPROFILE '.local\opt\opencode'
$localBin = Join-Path $env:USERPROFILE '.local\bin'
$binaryPath = Join-Path $installDir 'opencode.exe'

# The API also publishes -baseline variants for CPUs without AVX2.
$asset = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    'opencode-windows-arm64.zip'
} else {
    'opencode-windows-x64.zip'
}

# ── Resolve the published release ──────────────────────────────────────────

try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing
} catch {
    return @{ status = 'error'; message = "Could not read $manifestUrl : $($_.Exception.Message)" }
}

$file = $manifest.metadata.files.$asset
if (-not $file) {
    return @{ status = 'error'; message = "Release $($manifest.version) publishes no asset named $asset." }
}

$latestVersion = $manifest.version
Write-Host "Latest OpenCode: $latestVersion ($asset)" -ForegroundColor Cyan

# ── Compare against the installed binary ───────────────────────────────────

# `opencode --version` prints "opencode v2.2.6"; the manifest reports "2.2.6".
$installedVersion = $null
if (Test-Path $binaryPath) {
    $versionOutput = & $binaryPath --version 2>&1 | Select-Object -First 1
    if ($versionOutput -match '\d+\.\d+\.\d+') {
        $installedVersion = $Matches[0]
    }
}

if ($installedVersion -eq $latestVersion -and -not $Force) {
    Write-Host "OpenCode $installedVersion already installed at $installDir. Skipping install." -ForegroundColor Green
} else {
    if ($installedVersion) {
        Write-Host "Updating OpenCode: $installedVersion -> $latestVersion" -ForegroundColor Yellow
    } else {
        Write-Host "Installing OpenCode $latestVersion..." -ForegroundColor Yellow
    }

    $downloadDir = Join-Path $env:TEMP "install-opencode-$(Get-Date -Format yyyyMMdd-HHmmss)"
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

    try {
        $zip = Join-Path $downloadDir $asset
        Invoke-WebRequest -Uri $file.url -OutFile $zip -UseBasicParsing

        $actualHash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
        if ($actualHash -ne $file.sha256.ToLower()) {
            return @{
                status  = 'error'
                message = "Checksum mismatch for $asset : expected $($file.sha256), got $actualHash."
            }
        }
        Write-Host "Checksum verified." -ForegroundColor Green

        # The zip holds a single opencode.exe at its root. Extracted to a staging
        # folder first so a failed download cannot leave the install half-replaced.
        $extractDir = Join-Path $downloadDir 'extracted'
        Expand-Archive -Path $zip -DestinationPath $extractDir -Force

        $extracted = Join-Path $extractDir 'opencode.exe'
        if (-not (Test-Path $extracted)) {
            return @{ status = 'error'; message = "opencode.exe not found in $asset after extraction." }
        }

        if (Test-Path $installDir) {
            Remove-Item $installDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Move-Item -Path $extracted -Destination $binaryPath -Force
    } catch {
        return @{ status = 'error'; message = "Download or extraction failed: $($_.Exception.Message)" }
    } finally {
        Remove-Item $downloadDir -Recurse -Force -ErrorAction Ignore
    }
}

# ── Link into ~/.local/bin ─────────────────────────────────────────────────

if (-not (Test-Path $localBin)) {
    New-Item -ItemType Directory -Path $localBin -Force | Out-Null
}

$linkPath = Join-Path $localBin 'opencode.exe'
if (Test-Path $linkPath) {
    Remove-Item $linkPath -Force
}
try {
    New-Item -Path $linkPath -ItemType SymbolicLink -Target $binaryPath -Force | Out-Null
} catch {
    # Symlinks need elevation or Developer Mode; a copy keeps the CLI on PATH.
    Write-Host "Symlink failed, falling back to copy." -ForegroundColor Gray
    Copy-Item -Path $binaryPath -Destination $linkPath -Force
}

$opencodeVersion = & $binaryPath --version 2>&1 | Select-Object -First 1
return @{ status = 'success'; message = $opencodeVersion }
