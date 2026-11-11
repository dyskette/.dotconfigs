#Requires -Version 7
<#
.SYNOPSIS
Links the dotfiles into the locations applications read them from.

.DESCRIPTION
Reads links.jsonc and, for each entry, creates a junction (folders) or a
symbolic link (files) at the target pointing into this repository:

- a correct link is left alone;
- a link pointing elsewhere is replaced (only the link is removed);
- a real file or folder, or a hard link, is moved aside to
  <name>.bak-<timestamp>, never deleted.

Junctions need no special rights. Symbolic links need Administrator or
Developer Mode; without either, those entries fail with that reason. The
Dotfiles step runs elevated for this reason (steps.psd1).

Also creates ~/.local/bin and puts it on the user PATH, and runs each entry's
post command (e.g. 'bat cache --build') after linking.

.PARAMETER Filter
Only process these app names (and 'localbin' for ~/.local/bin).

.OUTPUTS
Dotconfigs.StepResult: Skipped when nothing changed, Success, or Partial /
Failed when some entries could not be linked or their post command failed.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Filter = @(),
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'links.jsonc'),
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$LocalBin = (Join-Path $env:USERPROFILE '.local\bin')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1')

$links = @((Read-Jsonc $ManifestPath).links)
$apps = @($links.app | Sort-Object -Unique) + 'localbin'
$unknown = @($Filter | Where-Object { $_ -notin $apps })
if ($unknown) {
    return New-StepResult Failed "Unknown app(s) in -Filter: $($unknown -join ', '). Known: $($apps -join ', ')."
}
$selected = { param($app) $Filter.Count -eq 0 -or $app -in $Filter }

$changes = [Collections.Generic.List[string]]::new()
$backups = [Collections.Generic.List[string]]::new()
$failures = [Collections.Generic.List[string]]::new()
$canSymlink = Test-CanCreateSymlink
$linked = 0

if (& $selected 'localbin') {
    try {
        if (-not (Test-Path -LiteralPath $LocalBin)) {
            New-Item -ItemType Directory -Path $LocalBin -Force | Out-Null
            $changes.Add("created $LocalBin")
        }
        if (Add-PathEntry -Path $LocalBin) { $changes.Add("added $LocalBin to PATH") }
    } catch {
        $failures.Add("localbin: $($_.Exception.Message)")
    }
}

foreach ($link in $links | Where-Object { & $selected $_.app }) {
    $label = "[$($link.app)] $($link.source)"
    $source = Join-Path $RepositoryRoot $link.source
    $target = [Environment]::ExpandEnvironmentVariables($link.target)
    try {
        if ($link.type -notin 'Junction', 'SymbolicLink') { throw "unknown link type '$($link.type)'" }
        if (-not (Test-Path -LiteralPath $source)) { throw "source not found: $source" }
        $isFolder = Test-Path -LiteralPath $source -PathType Container
        if ($link.type -eq 'Junction' -and -not $isFolder) { throw 'a junction needs a folder source' }
        if ($link.type -eq 'SymbolicLink' -and -not $canSymlink) {
            $current = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            $alreadyOk = $current -and $current.LinkType -eq 'SymbolicLink' -and (@($current.Target) -contains $source)
            if (-not $alreadyOk) { throw 'symbolic links need Administrator or Developer Mode' }
        }

        $outcome = Set-Link -Source $source -Target $target -Type $link.type
        switch ($outcome) {
            'Unchanged' { }
            'BackedUp' {
                $backups.Add($target)
                $changes.Add("$label (existing $target moved to a .bak-* backup)")
            }
            default { if ($outcome) { $changes.Add("$label $($outcome.ToLower())") } }
        }
        if ($outcome -and $outcome -ne 'Unchanged') { Write-Info "$label -> $target ($outcome)" }
        $linked++
    } catch {
        Write-Warning "$label : $($_.Exception.Message)"
        $failures.Add("$label ($($_.Exception.Message))")
        continue
    }

    # Filtered: for a link without 'post', @($null) would be one $null element, not empty.
    $post = @($link.PSObject.Properties['post']?.Value | Where-Object { $_ })
    if ($post.Count -gt 0 -and $PSCmdlet.ShouldProcess($post -join ' ', 'Run')) {
        if (-not (Get-Command $post[0] -ErrorAction SilentlyContinue)) {
            $failures.Add("[$($link.app)] post command: $($post[0]) is not on PATH")
            continue
        }
        $result = Invoke-Native -FilePath $post[0] -Arguments @($post | Select-Object -Skip 1) -Quiet -NoThrow
        if (-not $result.Succeeded) {
            $tail = ($result.Output | Select-Object -Last 5) -join ' / '
            Write-Warning "[$($link.app)] '$($post -join ' ')' exited with $($result.ExitCode): $tail"
            $failures.Add("[$($link.app)] '$($post -join ' ')' exited with $($result.ExitCode)")
        }
    }
}

$data = @{ Changes = $changes.ToArray(); BackedUp = $backups.ToArray(); Failures = $failures.ToArray() }
if ($failures.Count -gt 0) {
    $status = if ($linked -gt 0) { 'Partial' } else { 'Failed' }
    return New-StepResult $status "Failed: $($failures -join '; ')." -Data $data
}
if ($changes.Count -eq 0) {
    return New-StepResult Skipped 'All links were already in place.' -Data $data
}
$note = if ($backups.Count -gt 0) { " Existing files were moved aside: $($backups -join ', ')." } else { '' }
return New-StepResult Success "$($changes.Count) change(s).$note" -Data $data
