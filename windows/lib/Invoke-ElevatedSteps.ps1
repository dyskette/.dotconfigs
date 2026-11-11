#Requires -Version 7
<#
.SYNOPSIS
Runs a group of setup steps in an elevated process. Internal: started by
Invoke-ElevatedStepBatch in StepRunner.psm1, not meant to be run by hand.

.DESCRIPTION
Writes the batch result (Outcomes, StopReason, LogPath) to ResultPath as CliXml.
Refuses to run anything when the elevated process belongs to a different user
than the one that asked for it (an over-the-shoulder admin account): user
profile paths and HKCU would then point at the wrong account.

.PARAMETER StepTablePath
Path to windows/steps.psd1.

.PARAMETER StepNames
Comma-separated step names. A single string because pwsh -File passes every
argument as a string.

.PARAMETER ResultPath
Where to write the CliXml result.

.PARAMETER ExpectedUserSid
SID of the user that started the run.

.PARAMETER LogDirectory
Directory for this process's transcript.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StepTablePath,
    [Parameter(Mandatory)][string]$StepNames,
    [Parameter(Mandatory)][string]$ResultPath,
    [Parameter(Mandatory)][string]$ExpectedUserSid,
    [Parameter(Mandatory)][string]$LogDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'StepRunner.psm1')

$logPath = Start-DotconfigsLog -LogDirectory $LogDirectory -Suffix 'elevated'
try {
    $table = @(Import-StepTable -Path $StepTablePath)
    $steps = foreach ($name in $StepNames -split ',') {
        $step = $table | Where-Object Name -eq $name
        if (-not $step) { throw "Unknown step '$name'." }
        $step
    }

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $refusal = if ($currentSid -ne $ExpectedUserSid) {
        "Elevated as a different user ($currentSid, expected $ExpectedUserSid). Sign in as an administrator, or run from an elevated prompt as the target user."
    } elseif (-not (Test-IsAdministrator)) {
        'The process is not elevated.'
    }

    $batch = if ($refusal) {
        Write-Warning $refusal
        [pscustomobject]@{
            Outcomes   = @($steps | ForEach-Object { New-StepOutcome -Step $_ -Result (New-StepResult Failed $refusal) })
            StopReason = $null
            LogPath    = $null
        }
    } else {
        Invoke-StepBatch -Steps $steps -ScriptRoot (Split-Path $StepTablePath -Parent)
    }
    $batch.LogPath = $logPath

    # Depth covers batch > Outcomes > outcome > Result > Data.
    $batch | Export-Clixml -LiteralPath $ResultPath -Depth 8
} finally {
    Stop-Transcript | Out-Null
}
