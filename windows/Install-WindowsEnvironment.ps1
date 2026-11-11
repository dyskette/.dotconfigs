#Requires -Version 7
<#
.SYNOPSIS
Sets up the Windows development environment.

.DESCRIPTION
Runs the steps declared in steps.psd1, in order. Run it as your normal user:
steps marked Admin run together in one elevated window (one UAC prompt), the
rest run here. Every step is safe to re-run, so after a failure or a restart
run the same command again and finished steps are skipped.

A transcript is written to ~/.local/state/dotconfigs/logs (the elevated part
gets its own '-elevated' log); the last 10 are kept.

Exit codes:
  0     every step succeeded or had nothing to do
  1     at least one step failed or partly failed (see the summary)
  3010  a step needs a restart; restart and run the same command again

.PARAMETER Skip
Step names or tags to leave out, e.g. -Skip packages or -Skip Font,Extensions.

.PARAMETER Only
Run only these step names or tags.

.PARAMETER InstallWSL
Include the opt-in WSL steps (tag 'wsl').

.PARAMETER LogDirectory
Where transcripts are written.

.PARAMETER SkipPackages
Same as -Skip packages. Kept, like the other -Skip* switches, for existing
commands and documentation.

.EXAMPLE
./Install-WindowsEnvironment.ps1 -WhatIf
Shows the plan without running anything.

.EXAMPLE
./Install-WindowsEnvironment.ps1 -Only Dotfiles,Font
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Skip = @(),
    [string[]]$Only = @(),
    [switch]$InstallWSL,
    [string]$LogDirectory = (Join-Path $env:USERPROFILE '.local\state\dotconfigs\logs'),

    [switch]$SkipPackages,
    [switch]$SkipGitHubPackages,
    [switch]$SkipOpenCode,
    [switch]$SkipConfiguration,
    [switch]$SkipFont,
    [switch]$SkipWindowsSettings,
    [switch]$SkipExtensions,
    [switch]$SkipNodeSetup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\StepRunner.psm1') -Force

$minimumBuild = 19041
$build = [Environment]::OSVersion.Version.Build
if ($build -lt $minimumBuild) {
    Write-Error "Windows 10 version 2004 (build $minimumBuild) or later is required; this is build $build." -ErrorAction Continue
    exit 1
}

# ── Select steps ────────────────────────────────────────────────────────────

$legacySwitches = [ordered]@{
    SkipPackages        = 'packages'
    SkipGitHubPackages  = 'GitHubReleases'
    SkipOpenCode        = 'OpenCode'
    SkipConfiguration   = 'Dotfiles'
    SkipFont            = 'Font'
    SkipWindowsSettings = 'WindowsSettings'
    SkipExtensions      = 'Extensions'
    SkipNodeSetup       = 'NodeLTS'
}
foreach ($switch in $legacySwitches.Keys) {
    if ($PSBoundParameters.ContainsKey($switch) -and $PSBoundParameters[$switch]) {
        $Skip += $legacySwitches[$switch]
    }
}

$stepTablePath = Join-Path $PSScriptRoot 'steps.psd1'
try {
    $table = @(Import-StepTable -Path $stepTablePath)
    $steps = @(Select-Step -Steps $table -Skip $Skip -Only $Only -Include @(if ($InstallWSL) { 'wsl' }))
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}

$isElevated = Test-IsAdministrator
$batches = @(Split-StepBatch -Steps $steps -IsElevated:$isElevated)

Write-StepPlan -Batches $batches
if ($isElevated) {
    Write-Info 'Running as Administrator: every step runs in this process. Run as your normal user to keep user-level steps unelevated.'
}
if ($steps.Count -eq 0) { exit 0 }

if (-not $PSCmdlet.ShouldProcess('this machine', "Run $($steps.Count) setup step(s)")) {
    exit 0
}

# ── Run ─────────────────────────────────────────────────────────────────────

$logPaths = [Collections.Generic.List[string]]::new()
$logPaths.Add((Start-DotconfigsLog -LogDirectory $LogDirectory))
$outcomes = [Collections.Generic.List[object]]::new()
$stopReason = $null

try {
    foreach ($batch in $batches) {
        $result = if ($batch.Elevate) {
            Invoke-ElevatedStepBatch -Steps $batch.Steps -StepTablePath $stepTablePath -LogDirectory $LogDirectory
        } else {
            Invoke-StepBatch -Steps $batch.Steps -ScriptRoot $PSScriptRoot
        }
        $outcomes.AddRange([object[]]@($result.Outcomes))
        if ($result.LogPath) { $logPaths.Add($result.LogPath) }
        if ($result.StopReason) {
            $stopReason = $result.StopReason
            break
        }
    }
} finally {
    $ran = @($outcomes | ForEach-Object Step)
    $notRun = @($steps | Where-Object { $_.Name -notin $ran })
    Write-RunSummary -Outcomes $outcomes -NotRun $notRun -LogPaths $logPaths

    switch ($stopReason) {
        'RestartRequired' {
            Write-Host 'Restart Windows, then run the same command again to continue:' -ForegroundColor Yellow
            $quote = { param($value) "'" + ([string]$value -replace "'", "''") + "'" }
            $rerun = @('&', (& $quote $PSCommandPath))
            foreach ($parameter in $PSBoundParameters.GetEnumerator()) {
                $value = $parameter.Value
                if ($value -is [switch]) {
                    if ($value) { $rerun += "-$($parameter.Key)" }
                } elseif ($value -is [array]) {
                    $rerun += "-$($parameter.Key) " + (($value | ForEach-Object { & $quote $_ }) -join ',')
                } else {
                    $rerun += "-$($parameter.Key) " + (& $quote $value)
                }
            }
            Write-Host "  $($rerun -join ' ')" -ForegroundColor Yellow
        }
        'CriticalFailure' {
            Write-Host 'Stopped: a step that later steps depend on failed.' -ForegroundColor Red
        }
    }
    Stop-Transcript | Out-Null
}

$exitCode = Get-RunExitCode -Outcomes $outcomes
switch ($exitCode) {
    0 { Write-Success 'Setup complete. Open a new shell to pick up PATH changes.' }
    1 { Write-Host 'Setup finished with failures. Fix them and run the same command again.' -ForegroundColor Red }
}
exit $exitCode
