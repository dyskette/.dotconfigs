#Requires -Version 7
<#
.SYNOPSIS
Installs the VS Code and Visual Studio extensions declared in the repo.

.DESCRIPTION
VS Code: the "extensions" and "windows" lists of vscode/extensions.json are
installed with the 'code' CLI when missing. VS Code keeps installed extensions
up to date on its own, so they are not reinstalled.

Visual Studio: entries of vs/extensions.jsonc are Marketplace ids (downloaded
as .vsix through the Marketplace API, since Visual Studio has no install-by-id
verb) or repo-relative .vsix paths. The identity inside each package decides
whether it is already installed at that version; VSIXInstaller.exe installs the
rest. Visual Studio must be closed for that.

.PARAMETER Editors
Which editors to handle: code, vs.

.PARAMETER Extensions
Additional VS Code extension ids.

.PARAMETER CustomOnly
Install only -Extensions, not the manifests.

.OUTPUTS
Dotconfigs.StepResult
#>
[CmdletBinding()]
param(
    [ValidateSet('code', 'vs')]
    [string[]]$Editors = @('code', 'vs'),
    [string[]]$Extensions = @(),
    [switch]$CustomOnly,
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

# Per-editor outcome: Installed / Current / Failed name lists, or Skipped with a reason.
$report = [ordered]@{}

<#
.SYNOPSIS
Reads the Id and Version from a .vsix package manifest, or $null.

.DESCRIPTION
That identity, not the Marketplace itemName, is what an installed extension
records on disk, so it is the only value both sides can be compared on. A file
without one is not a valid VSIX (e.g. an HTML error page saved as .vsix).
#>
function Get-VsixIdentity([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try { $zip = [IO.Compression.ZipFile]::OpenRead($Path) } catch { return $null }
    try {
        $entry = $zip.Entries | Where-Object FullName -eq 'extension.vsixmanifest' | Select-Object -First 1
        if (-not $entry) { return $null }
        $reader = [IO.StreamReader]::new($entry.Open())
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
Extension Id -> installed version for a Visual Studio instance (per-user and machine-wide).
#>
function Get-InstalledVsix([string]$VsPath, [string]$InstanceId) {
    $roots = @(Join-Path $VsPath 'Common7\IDE\Extensions')
    $roots += Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio') -Directory -Filter "*_$InstanceId" -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'Extensions' }
    $installed = @{}
    foreach ($root in $roots | Where-Object { Test-Path -LiteralPath $_ }) {
        foreach ($manifest in Get-ChildItem -LiteralPath $root -Filter 'extension.vsixmanifest' -Recurse -Depth 1 -ErrorAction SilentlyContinue) {
            # One malformed manifest must not abort the scan: a missed entry only
            # costs a redundant reinstall.
            try {
                $identity = ([xml](Get-Content -LiteralPath $manifest.FullName -Raw)).PackageManifest.Metadata.Identity
                if ($identity.Id) { $installed[$identity.Id] = $identity.Version }
            } catch { Write-Verbose "Unreadable manifest $($manifest.FullName): $($_.Exception.Message)" }
        }
    }
    return $installed
}

# ── VS Code ─────────────────────────────────────────────────────────────────

if ('code' -in $Editors) {
    $wanted = @($Extensions)
    if (-not $CustomOnly) {
        $manifest = Read-Jsonc (Join-Path $RepositoryRoot 'vscode\extensions.json')
        $wanted += @($manifest.extensions) + @($manifest.windows)
    }
    $wanted = @($wanted | Where-Object { $_ } | Sort-Object -Unique)

    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        $report.code = @{ Skipped = 'VS Code (code) is not on PATH' }
    } elseif ($wanted.Count -gt 0) {
        $entry = @{ Installed = @(); Current = @(); Failed = @() }
        $present = @((Invoke-Native -FilePath code -Arguments @('--list-extensions') -Quiet).Output)
        foreach ($id in $wanted) {
            if ($present -contains $id) { $entry.Current += $id; continue }
            $result = Invoke-Native -FilePath code -Arguments @('--install-extension', $id) -Quiet -NoThrow
            if ($result.Succeeded) {
                Write-Info "VS Code: installed $id"
                $entry.Installed += $id
            } else {
                Write-Warning "VS Code: $id failed: $(($result.Output | Select-Object -Last 3) -join ' / ')"
                $entry.Failed += "$id (exit $($result.ExitCode))"
            }
        }
        $report.code = $entry
    }
}

# ── Visual Studio ───────────────────────────────────────────────────────────

if ('vs' -in $Editors -and -not $CustomOnly) {
    $vsEntries = @((Read-Jsonc (Join-Path $RepositoryRoot 'vs\extensions.jsonc')).extensions)
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $instance = $null
    if (Test-Path -LiteralPath $vswhere) {
        $json = (Invoke-Native -FilePath $vswhere -Quiet -Arguments @(
                '-latest', '-products', 'Microsoft.VisualStudio.Product.Enterprise', '-version', '[18.0,19.0)', '-format', 'json')).Output -join ''
        $instance = @($json | ConvertFrom-Json) | Select-Object -First 1
    }

    if ($vsEntries.Count -eq 0) {
        # Nothing declared.
    } elseif (-not $instance) {
        $report.vs = @{ Skipped = 'Visual Studio 2026 Enterprise is not installed' }
    } elseif (Get-Process devenv -ErrorAction SilentlyContinue) {
        $report.vs = @{ Installed = @(); Current = @(); Failed = @('Visual Studio is running; close it and run again') }
    } else {
        $entry = @{ Installed = @(); Current = @(); Failed = @() }
        $installedVsix = Get-InstalledVsix -VsPath $instance.installationPath -InstanceId $instance.instanceId
        $vsixInstaller = Join-Path $instance.installationPath 'Common7\IDE\VSIXInstaller.exe'
        $workDir = New-WorkDirectory -Prefix 'dotconfigs-vsix'
        try {
            foreach ($item in $vsEntries) {
                $path = $item.PSObject.Properties['path']?.Value
                $id = $item.PSObject.Properties['id']?.Value
                $label = $item.PSObject.Properties['name']?.Value ?? $id ?? $path
                try {
                    if ($path) {
                        $vsix = Join-Path $RepositoryRoot $path
                        if (-not (Test-Path -LiteralPath $vsix)) { throw "package not found: $vsix" }
                    } else {
                        $publisher, $extension = $id.Split('.', 2)
                        if (-not $extension) { throw "'$id' is not in publisher.extension form" }
                        $version = $item.PSObject.Properties['version']?.Value ?? 'latest'
                        $vsix = Invoke-Download -OutFile (Join-Path $workDir "$id.vsix") -Uri (
                            "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$publisher" +
                            "/vsextensions/$extension/$version/vspackage")
                    }

                    # The Marketplace publishes no checksum; a package without a
                    # readable identity is not a VSIX and is not handed over.
                    $identity = Get-VsixIdentity $vsix
                    if (-not $identity) { throw 'the package has no readable extension.vsixmanifest' }
                    if ($installedVsix[$identity.Id] -eq $identity.Version) { $entry.Current += $label; continue }

                    # Scoped to the instance: extensions whose manifest also targets
                    # other installer products (SSMS) would otherwise go there too.
                    $arguments = '/quiet /instanceIds:{0} {1}' -f $instance.instanceId, (ConvertTo-CommandLineArgument $vsix)
                    $exit = (Start-Process -FilePath $vsixInstaller -ArgumentList $arguments -Wait -PassThru -NoNewWindow).ExitCode
                    if ($exit -ne 0) { throw "VSIXInstaller exited with $exit (logs: $env:TEMP\dd_VSIXInstaller*.log)" }
                    Write-Info "Visual Studio: installed $label"
                    $entry.Installed += $label
                } catch {
                    Write-Warning "Visual Studio: $label failed: $($_.Exception.Message)"
                    $entry.Failed += "$label ($($_.Exception.Message))"
                }
            }
        } finally {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue # safe: private temp dir from New-WorkDirectory
        }
        $report.vs = $entry
    }
}

# ── Result ──────────────────────────────────────────────────────────────────

$parts = foreach ($editor in $report.Keys) {
    $entry = $report[$editor]
    if ($entry.ContainsKey('Skipped')) { "${editor}: skipped ($($entry.Skipped))"; continue }
    "${editor}: $($entry.Installed.Count) installed, $($entry.Current.Count) current, $($entry.Failed.Count) failed"
}
$failures = @($report.Values | Where-Object { $_.ContainsKey('Failed') } | ForEach-Object { $_.Failed })
$installedCount = @($report.Values | Where-Object { $_.ContainsKey('Installed') } | ForEach-Object { $_.Installed }).Count
$okCount = $installedCount + @($report.Values | Where-Object { $_.ContainsKey('Current') } | ForEach-Object { $_.Current }).Count
$message = if ($parts) { ($parts -join '; ') + '.' } else { 'No extensions declared.' }
$data = @{ Editors = $report }

if ($failures.Count -gt 0) {
    $status = if ($okCount -gt 0) { 'Partial' } else { 'Failed' }
    return New-StepResult $status "$message Failed: $($failures -join '; ')." -Data $data
}
if ($installedCount -eq 0) { return New-StepResult Skipped $message -Data $data }
return New-StepResult Success $message -Data $data
