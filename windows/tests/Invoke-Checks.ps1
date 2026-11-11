#Requires -Version 7
<#
.SYNOPSIS
Runs PSScriptAnalyzer and the Pester tests for the PowerShell scripts.

.DESCRIPTION
Lint: every PowerShell file in the repo is analyzed with the root
PSScriptAnalyzerSettings.psd1. Findings fail the run, except in files listed in
QualityBaseline.psd1, where they are only reported.

Test: runs the Pester 5 tests in this folder, with code coverage for every
script under windows/ that is not in the legacy baseline.

With neither -Lint nor -Test, both run.

.PARAMETER Lint
Run PSScriptAnalyzer.

.PARAMETER Test
Run Pester.

.PARAMETER CI
Write NUnit test results and a coverage report to windows/tests/out, and print
legacy lint findings in full.

.EXAMPLE
./windows/tests/Invoke-Checks.ps1

.EXAMPLE
./windows/tests/Invoke-Checks.ps1 -Lint
#>
[CmdletBinding()]
param(
    [switch]$Lint,
    [switch]$Test,
    [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'TestSupport.psm1') -Force

if (-not $Lint -and -not $Test) {
    $Lint = $true
    $Test = $true
}

$root = Get-RepoRoot
$failed = $false

if ($Lint) {
    Import-Module PSScriptAnalyzer -MinimumVersion 1.22

    Write-Host '=== PSScriptAnalyzer ===' -ForegroundColor Cyan
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $legacy = @(Get-LegacyScript)
    $strictFindings = 0
    $legacyFindings = 0

    foreach ($file in Get-PowerShellFile) {
        $findings = @(Invoke-ScriptAnalyzer -Path (Join-Path $root $file) -Settings $settings)
        if ($findings.Count -eq 0) { continue }

        if ($file -in $legacy) {
            $legacyFindings += $findings.Count
            $summary = ($findings | Group-Object RuleName | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
            Write-Host "  [legacy] ${file}: $summary" -ForegroundColor DarkYellow
            if ($CI) {
                $findings | ForEach-Object { Write-Host "      line $($_.Line): $($_.RuleName)" -ForegroundColor DarkGray }
            }
        } else {
            $strictFindings += $findings.Count
            foreach ($finding in $findings) {
                Write-Host "  ${file}:$($finding.Line) [$($finding.Severity)] $($finding.RuleName)" -ForegroundColor Red
                Write-Host "      $($finding.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "Strict findings: $strictFindings. Legacy findings (not failing): $legacyFindings." `
        -ForegroundColor ($strictFindings -gt 0 ? 'Red' : 'Green')
    if ($strictFindings -gt 0) { $failed = $true }
}

if ($Test) {
    Import-Module Pester -MinimumVersion 5.6

    Write-Host ''
    Write-Host '=== Pester ===' -ForegroundColor Cyan
    $config = New-PesterConfiguration
    $config.Run.Path = $PSScriptRoot
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.CodeCoverage.Enabled = $true
    # Rewritten scripts only: legacy ones have no tests yet, and the list grows
    # as files leave QualityBaseline.psd1.
    $legacy = @(Get-LegacyScript)
    $config.CodeCoverage.Path = @(Get-PowerShellFile |
            Where-Object { $_ -like 'windows/*' -and $_ -notlike 'windows/tests/*' -and $_ -match '\.ps(m)?1$' -and $_ -notin $legacy } |
            ForEach-Object { Join-Path $root $_ })
    $config.CodeCoverage.CoveragePercentTarget = 75

    $outDir = Join-Path $PSScriptRoot 'out'
    if ($CI) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        $config.TestResult.Enabled = $true
        $config.TestResult.OutputFormat = 'NUnitXml'
        $config.TestResult.OutputPath = Join-Path $outDir 'test-results.xml'
        $config.CodeCoverage.OutputPath = Join-Path $outDir 'coverage.xml'
    } else {
        # Pester writes coverage.xml to the current directory unless told otherwise.
        $config.CodeCoverage.OutputPath = Join-Path ([IO.Path]::GetTempPath()) 'dotconfigs-coverage.xml'
    }

    $result = Invoke-Pester -Configuration $config
    if ($result.Result -ne 'Passed') { $failed = $true }
}

if ($failed) {
    Write-Host ''
    Write-Host 'Checks failed.' -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host 'All checks passed.' -ForegroundColor Green
