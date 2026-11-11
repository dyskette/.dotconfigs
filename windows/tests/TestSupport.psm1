#Requires -Version 7
<#
.SYNOPSIS
Repository helpers shared by Invoke-Checks.ps1 and the Pester tests.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
Absolute path of the repository root.
#>
function Get-RepoRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

<#
.SYNOPSIS
PowerShell files in the repository, as repo-relative paths with '/' separators.

.DESCRIPTION
Asks git for tracked and untracked-but-not-ignored files, so modules installed
under the gitignored powershell/Modules folder are never linted or tested.
#>
function Get-PowerShellFile {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $root = Get-RepoRoot
    $files = & git -C $root ls-files --cached --others --exclude-standard -- '*.ps1' '*.psm1' '*.psd1'
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed with exit code $LASTEXITCODE."
    }
    # A file deleted in the working tree is still listed by --cached.
    $files | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) } | Sort-Object -Unique
}

<#
.SYNOPSIS
Repo-relative paths of scripts still exempt from the conventions.
#>
function Get-LegacyScript {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $baseline = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'QualityBaseline.psd1')
    $baseline.Legacy
}

Export-ModuleMember -Function Get-RepoRoot, Get-PowerShellFile, Get-LegacyScript
