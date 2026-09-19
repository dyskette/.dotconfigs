#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Installs extensions for VS Code and Visual Studio

.DESCRIPTION
    VS Code extensions are read from vscode/extensions.json and installed with
    the editor CLI.

    Visual Studio extensions are read from vs/extensions.jsonc. Visual Studio
    exposes no marketplace-id install verb, so each entry is resolved to a .vsix
    download from the Marketplace REST API and handed to VSIXInstaller.exe.

.NOTES
    Requirements:
    - VS Code on PATH for the "code" target
    - Visual Studio 2026 installed, and closed, for the "vs" target
    - Internet connection for extension downloads
#>

param(
    [Parameter(HelpMessage="Which editors to install extensions for")]
    [ValidateSet("code", "vs")]
    [string[]]$Editors = @("code", "vs"),

    [Parameter(HelpMessage="Additional VS Code extensions to install")]
    [string[]]$Extensions = @(),

    [Parameter(HelpMessage="Skip manifest extensions and only install custom ones")]
    [switch]$CustomOnly,

    [Parameter(HelpMessage="Force reinstall of extensions")]
    [switch]$Force
)

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

$dotfilesRoot = Split-Path $PSScriptRoot -Parent

# ── Visual Studio helpers ───────────────────────────────────────────────────

<#
.SYNOPSIS
    Reads the Id and Version from a .vsix package manifest.

.DESCRIPTION
    A VSIX is a zip whose extension.vsixmanifest carries the extension identity.
    That identity, not the Marketplace itemName, is what an installed extension
    records on disk, so it is the only value both sides can be compared on.

.PARAMETER Path
    Path to the .vsix file.

.OUTPUTS
    Hashtable with Id and Version, or $null when the manifest is unreadable.
#>
function Get-VsixIdentity {
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq "extension.vsixmanifest" } | Select-Object -First 1
        if (-not $entry) { return $null }

        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $xml = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        $zip.Dispose()
    }

    $identity = $xml.PackageManifest.Metadata.Identity
    if (-not $identity) { return $null }
    return @{ Id = $identity.Id; Version = $identity.Version }
}

<#
.SYNOPSIS
    Maps the extension identities already installed for a Visual Studio instance.

.DESCRIPTION
    Extensions land in one of two roots: the per-instance user directory, or the
    installation Extensions directory for machine-wide (/admin) installs. Both
    are scanned so an extension installed either way is detected.

.PARAMETER VsPath
    Installation path of the Visual Studio instance.

.PARAMETER InstanceId
    vswhere instanceId, used to locate the per-user extension directory.

.OUTPUTS
    Hashtable keyed by extension Id, valued by installed version.
#>
function Get-InstalledVsix {
    param(
        [Parameter(Mandatory)][string]$VsPath,
        [string]$InstanceId
    )

    $roots = @(Join-Path $VsPath "Common7" "IDE" "Extensions")
    if ($InstanceId) {
        $roots += Get-ChildItem (Join-Path $env:LOCALAPPDATA "Microsoft" "VisualStudio") -Directory `
            -Filter "*_$InstanceId" -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "Extensions" }
    }

    $installed = @{}
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Filter "extension.vsixmanifest" -Recurse -Depth 1 -ErrorAction SilentlyContinue |
            ForEach-Object {
                # One malformed manifest must not abort the scan: a missed entry
                # costs a redundant reinstall, an aborted scan costs them all.
                try {
                    $identity = ([xml](Get-Content $_.FullName -Raw)).PackageManifest.Metadata.Identity
                    if ($identity.Id) { $installed[$identity.Id] = $identity.Version }
                } catch { }
            }
    }

    return $installed
}

<#
.SYNOPSIS
    Installs a Visual Studio extension from the Marketplace or a local package.

.PARAMETER MarketplaceId
    itemName from the Marketplace URL, in publisher.extension form. Mutually
    exclusive with LocalPath.

.PARAMETER LocalPath
    Path to a .vsix already on disk, for extensions built in this repo rather
    than published. Mutually exclusive with MarketplaceId.

.PARAMETER VsPath
    Installation path of the target Visual Studio instance.

.PARAMETER Version
    Version to fetch from the Marketplace, or "latest". Ignored for LocalPath.

.PARAMETER SkuName
    Edition to scope the install to. Extensions whose manifest also targets
    other products registered with the VS Installer (SSMS, for one) would
    otherwise be offered to those as well.

.PARAMETER InstalledVsix
    Identity map from Get-InstalledVsix, used to skip what is already present.

.OUTPUTS
    Hashtable with status, and message describing the outcome.
#>
function Install-VsExtension {
    param(
        [Parameter(Mandatory)][string]$VsPath,
        [string]$MarketplaceId,
        [string]$LocalPath,
        [string]$Version = "latest",
        [string]$SkuName = "Enterprise",
        [hashtable]$InstalledVsix = @{},
        [switch]$Force
    )

    # A local package is used in place, never deleted afterwards.
    $isTemporary = -not $LocalPath

    if ($LocalPath) {
        if (-not (Test-Path $LocalPath)) {
            return @{ status = "failed"; message = "Package not found: $LocalPath" }
        }
        $vsix = $LocalPath
    } else {
        $parts = $MarketplaceId.Split([char]46, 2)
        if ($parts.Count -ne 2) {
            return @{ status = "failed"; message = "Not in publisher.extension form: $MarketplaceId" }
        }
        $publisher, $extension = $parts

        $vsix = Join-Path ([System.IO.Path]::GetTempPath()) "$MarketplaceId.vsix"
        $uri = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$publisher" +
               "/vsextensions/$extension/$Version/vspackage"

        try {
            Invoke-WebRequest -Uri $uri -OutFile $vsix -ErrorAction Stop
        } catch {
            return @{ status = "failed"; message = "Download failed: $($_.Exception.Message)" }
        }
    }

    # The identity is only knowable from the package itself, so the
    # already-installed check has to happen after the download, not before it.
    # It also covers the local case: a rebuilt package with a bumped version
    # reinstalls, an unchanged one is skipped.
    $identity = Get-VsixIdentity -Path $vsix
    if (-not $Force -and $identity -and $InstalledVsix.ContainsKey($identity.Id) -and
        $InstalledVsix[$identity.Id] -eq $identity.Version) {
        if ($isTemporary) { Remove-Item $vsix -Force -ErrorAction SilentlyContinue }
        return @{ status = "skipped"; message = "$($identity.Id) $($identity.Version) already installed" }
    }

    $vsixInstaller = Join-Path $VsPath "Common7" "IDE" "VSIXInstaller.exe"
    if (-not (Test-Path $vsixInstaller)) {
        if ($isTemporary) { Remove-Item $vsix -Force -ErrorAction SilentlyContinue }
        return @{ status = "failed"; message = "VSIXInstaller.exe not found at $vsixInstaller" }
    }

    # Start-Process joins -ArgumentList with spaces without quoting, so the
    # package path has to carry its own quotes.
    $arguments = @("/quiet", "/skuName:$SkuName", "`"$vsix`"")
    $process = Start-Process -FilePath $vsixInstaller -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    if ($isTemporary) { Remove-Item $vsix -Force -ErrorAction SilentlyContinue }

    if ($process.ExitCode -eq 0) {
        $what = if ($LocalPath) { Split-Path $LocalPath -Leaf } else { $MarketplaceId }
        return @{ status = "success"; message = "Installed $what" }
    }
    return @{
        status  = "failed"
        message = "VSIXInstaller exited with $($process.ExitCode). Logs: $env:TEMP\VSIXInstaller*.log"
    }
}

# ── Load manifests ──────────────────────────────────────────────────────────

Write-Host "=== Editor Extensions Installation ===" -ForegroundColor Cyan

# VS Code
$defaultExtensions = @()
$extensionsJsonPath = Join-Path $dotfilesRoot "vscode\extensions.json"

if ($Editors -notcontains "code") {
    # Nothing to load: reporting a VS Code extension count under -Editors vs
    # only invites the reader to look for installs that never happen.
} elseif (Test-Path $extensionsJsonPath) {
    try {
        Write-Host "Loading extensions from: $extensionsJsonPath" -ForegroundColor Gray
        $extensionsJson = Get-Content $extensionsJsonPath -Raw | ConvertFrom-Json
        $defaultExtensions = @($extensionsJson.extensions) + @($extensionsJson.windows)
        Write-Host "Loaded $($defaultExtensions.Count) extensions" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to load extensions.json: $_"
        $defaultExtensions = @("eamodio.gitlens", "asvetliakov.vscode-neovim", "ms-vscode.powershell")
    }
} else {
    Write-Warning "extensions.json not found at: $extensionsJsonPath"
    $defaultExtensions = @("eamodio.gitlens", "asvetliakov.vscode-neovim", "ms-vscode.powershell")
}

# Visual Studio
$vsExtensions = @()
$vsExtensionsPath = Join-Path $dotfilesRoot "vs\extensions.jsonc"

if (($Editors -contains "vs") -and -not $CustomOnly) {
    if (Test-Path $vsExtensionsPath) {
        try {
            Write-Host "Loading extensions from: $vsExtensionsPath" -ForegroundColor Gray
            $vsExtensions = @((Get-Content $vsExtensionsPath -Raw | ConvertFrom-Json).extensions)
            Write-Host "Loaded $($vsExtensions.Count) Visual Studio extensions" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to load vs/extensions.jsonc: $_"
        }
    } else {
        Write-Warning "extensions.jsonc not found at: $vsExtensionsPath"
    }
}

# Build VS Code extension list
$extensionsToInstall = @()
if (-not $CustomOnly) {
    $extensionsToInstall += $defaultExtensions
}
if ($Extensions.Count -gt 0) {
    $extensionsToInstall += $Extensions
}

if ($extensionsToInstall.Count -eq 0 -and $vsExtensions.Count -eq 0) {
    Write-Host "No extensions specified for installation." -ForegroundColor Yellow
    return @{ status = "skipped"; message = "No extensions specified" }
}

$allResults = @{}

# ── VS Code ─────────────────────────────────────────────────────────────────

foreach ($editor in ($Editors | Where-Object { $_ -eq "code" })) {
    $editorName = "VS Code"

    if (-not (Get-Command $editor -ErrorAction SilentlyContinue)) {
        Write-Warning "$editorName ($editor) not found in PATH. Skipping."
        $allResults[$editor] = @{ status = "skipped"; message = "Not found in PATH" }
        continue
    }

    Write-Host ""
    Write-Host "Installing $editorName extensions..." -ForegroundColor Yellow

    $installedCount = 0
    $failedExtensions = @()
    $skippedExtensions = @()

    # Get already-installed extensions once
    $installedExtensions = @()
    if (-not $Force) {
        $installedExtensions = & $editor --list-extensions 2>$null
    }

    foreach ($extension in $extensionsToInstall) {
        if (-not $Force -and $installedExtensions -contains $extension) {
            Write-Host "  Already installed: $extension" -ForegroundColor Cyan
            $skippedExtensions += $extension
            continue
        }

        try {
            $installResult = & $editor --install-extension $extension --force 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Installed: $extension" -ForegroundColor Green
                $installedCount++
            } else {
                Write-Warning "  Failed: $extension - $installResult"
                $failedExtensions += $extension
            }
        } catch {
            Write-Warning "  Error: $extension - $_"
            $failedExtensions += $extension
        }
    }

    Write-Host ""
    Write-Host "$editorName Summary:" -ForegroundColor Cyan
    Write-Host "  Installed: $installedCount" -ForegroundColor Green
    Write-Host "  Skipped: $($skippedExtensions.Count)" -ForegroundColor Cyan
    Write-Host "  Failed: $($failedExtensions.Count)" -ForegroundColor $(if ($failedExtensions.Count -gt 0) { "Red" } else { "Green" })

    if ($failedExtensions.Count -gt 0) {
        $failedExtensions | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    }

    $status = if ($failedExtensions.Count -eq 0) { "success" } elseif ($installedCount -gt 0) { "partial" } else { "failed" }
    $allResults[$editor] = @{
        status = $status
        installed_count = $installedCount
        failed_count = $failedExtensions.Count
        skipped_count = $skippedExtensions.Count
        failed_extensions = $failedExtensions
    }
}

# ── Visual Studio ───────────────────────────────────────────────────────────

if ($vsExtensions.Count -gt 0) {
    Write-Host ""
    Write-Host "Installing Visual Studio extensions..." -ForegroundColor Yellow

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio" "Installer" "vswhere.exe"
    $vsPath = $null
    $vsInstanceId = $null
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products Microsoft.VisualStudio.Product.Enterprise `
            -version "[18.0,19.0)" -property installationPath | Select-Object -First 1
        $vsInstanceId = & $vswhere -latest -products Microsoft.VisualStudio.Product.Enterprise `
            -version "[18.0,19.0)" -property instanceId | Select-Object -First 1
    }

    if (-not $vsPath) {
        Write-Warning "Visual Studio 2026 Enterprise not found. Skipping."
        $allResults["vs"] = @{ status = "skipped"; message = "Visual Studio 2026 Enterprise not found" }
    } elseif (Get-Process devenv -ErrorAction SilentlyContinue) {
        # VSIXInstaller refuses to modify an instance that is in use.
        Write-Warning "Visual Studio is running. Close it and re-run. Skipping."
        $allResults["vs"] = @{ status = "skipped"; message = "Visual Studio is running" }
    } else {
        $installedVsix = Get-InstalledVsix -VsPath $vsPath -InstanceId $vsInstanceId

        $installedCount = 0
        $failedExtensions = @()
        $skippedExtensions = @()

        foreach ($entry in $vsExtensions) {
            $label = if ($entry.name) { $entry.name } elseif ($entry.id) { $entry.id } else { $entry.path }
            $version = if ($entry.version) { $entry.version } else { "latest" }

            # "path" is repo-relative so the manifest stays machine-independent.
            $arguments = @{ VsPath = $vsPath; InstalledVsix = $installedVsix; Force = $Force }
            if ($entry.path) {
                $arguments.LocalPath = Join-Path $dotfilesRoot $entry.path
            } else {
                $arguments.MarketplaceId = $entry.id
                $arguments.Version = $version
            }

            $result = Install-VsExtension @arguments

            switch ($result.status) {
                "success" {
                    Write-Host "  Installed: $label" -ForegroundColor Green
                    $installedCount++
                }
                "skipped" {
                    Write-Host "  Already installed: $label" -ForegroundColor Cyan
                    $skippedExtensions += $entry.id
                }
                default {
                    Write-Warning "  Failed: $label - $($result.message)"
                    $failedExtensions += $entry.id
                }
            }
        }

        Write-Host ""
        Write-Host "Visual Studio Summary:" -ForegroundColor Cyan
        Write-Host "  Installed: $installedCount" -ForegroundColor Green
        Write-Host "  Skipped: $($skippedExtensions.Count)" -ForegroundColor Cyan
        Write-Host "  Failed: $($failedExtensions.Count)" -ForegroundColor $(if ($failedExtensions.Count -gt 0) { "Red" } else { "Green" })

        if ($failedExtensions.Count -gt 0) {
            $failedExtensions | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
        }

        $status = if ($failedExtensions.Count -eq 0) { "success" } elseif ($installedCount -gt 0) { "partial" } else { "failed" }
        $allResults["vs"] = @{
            status = $status
            installed_count = $installedCount
            failed_count = $failedExtensions.Count
            skipped_count = $skippedExtensions.Count
            failed_extensions = $failedExtensions
        }
    }
}

# Overall status
$overallFailed = ($allResults.Values | Where-Object { $_.status -eq "failed" }).Count
$overallStatus = if ($overallFailed -eq $allResults.Count) { "failed" } elseif ($overallFailed -gt 0) { "partial" } else { "success" }

return @{
    status = $overallStatus
    message = "Extension installation completed"
    results = $allResults
}
