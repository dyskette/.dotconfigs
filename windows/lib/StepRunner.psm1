#Requires -Version 7
<#
.SYNOPSIS
Loads, selects and runs the setup steps declared in windows/steps.psd1.

.DESCRIPTION
A step is one script that returns one StepResult (see Common.psm1). Steps run
in table order. Consecutive steps with Admin = $true run together in a single
elevated child process, so a run asks for elevation once per group rather than
once per step.

Every run produces StepOutcome objects:
  Step, Description, Admin, Critical  copied from the table
  Result                              the StepResult
  Duration                            [timespan]
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

$script:StepKeys = @('Name', 'Script', 'Description', 'Admin', 'Critical', 'OptIn', 'Tags', 'Parameters')

# ── Step table ──────────────────────────────────────────────────────────────

<#
.SYNOPSIS
Reads and validates the step table.

.DESCRIPTION
Unknown keys are rejected so a typo ('Admim') fails loudly instead of silently
running a step unelevated.

.PARAMETER Path
Path to a .psd1 file holding @{ Steps = @( @{ Name = ...; Script = ... }, ... ) }.
#>
function Import-StepTable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $data = Import-PowerShellDataFile -Path $Path
    if (-not $data.ContainsKey('Steps') -or @($data.Steps).Count -eq 0) {
        throw "Step table $Path declares no Steps."
    }

    $seen = @{}
    foreach ($entry in $data.Steps) {
        $unknown = @($entry.Keys | Where-Object { $_ -notin $script:StepKeys })
        if ($unknown) {
            throw "Step '$($entry['Name'])' in $Path has unknown keys: $($unknown -join ', ')."
        }
        foreach ($required in 'Name', 'Script', 'Description') {
            if (-not $entry[$required]) { throw "A step in $Path has no $required." }
        }
        if ($seen.ContainsKey($entry.Name)) { throw "Step name '$($entry.Name)' appears twice in $Path." }
        $seen[$entry.Name] = $true

        [pscustomobject]@{
            PSTypeName  = 'Dotconfigs.Step'
            Name        = [string]$entry.Name
            Script      = [string]$entry.Script
            Description = [string]$entry.Description
            Admin       = [bool]$entry['Admin']
            Critical    = [bool]$entry['Critical']
            OptIn       = [bool]$entry['OptIn']
            Tags        = [string[]]@($entry['Tags'] | Where-Object { $_ })
            Parameters  = if ($entry['Parameters']) { [hashtable]$entry.Parameters } else { @{} }
        }
    }
}

<#
.SYNOPSIS
Filters the step table by name or tag, keeping table order.

.PARAMETER Skip
Step names or tags to leave out.

.PARAMETER Only
When given, only steps matching one of these names or tags run. Opt-in steps
matched here are included.

.PARAMETER Include
Names or tags of opt-in steps to add.
#>
function Select-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Steps,
        [string[]]$Skip = @(),
        [string[]]$Only = @(),
        [string[]]$Include = @()
    )

    $known = @($Steps.Name) + @($Steps | ForEach-Object { $_.Tags })
    $unknown = @(@($Skip) + @($Only) + @($Include) | Where-Object { $_ -and $_ -notin $known })
    if ($unknown) {
        throw "Unknown step or tag: $($unknown -join ', '). Known: $(($known | Sort-Object -Unique) -join ', ')."
    }

    $matches_ = {
        param($step, [string[]]$selectors)
        foreach ($selector in $selectors) {
            if ($step.Name -eq $selector -or $selector -in $step.Tags) { return $true }
        }
        return $false
    }

    foreach ($step in $Steps) {
        if ($Only.Count -gt 0) {
            if (-not (& $matches_ $step $Only)) { continue }
        } elseif ($step.OptIn -and -not (& $matches_ $step $Include)) {
            continue
        }
        if (& $matches_ $step $Skip) { continue }
        $step
    }
}

<#
.SYNOPSIS
Groups steps into runs that share the same privilege level.

.PARAMETER IsElevated
When the caller is already elevated everything runs in-process as one batch.

.OUTPUTS
Objects with Elevate ([bool]) and Steps (object[]), in execution order.
#>
function Split-StepBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Steps,
        [switch]$IsElevated
    )

    if ($Steps.Count -eq 0) { return }
    if ($IsElevated) {
        return [pscustomobject]@{ Elevate = $false; Steps = $Steps }
    }

    $current = $null
    foreach ($step in $Steps) {
        if ($null -eq $current -or $current.Elevate -ne $step.Admin) {
            if ($current) { $current }
            $current = [pscustomobject]@{ Elevate = $step.Admin; Steps = [Collections.Generic.List[object]]::new() }
        }
        $current.Steps.Add($step)
    }
    $current
}

# ── Results ─────────────────────────────────────────────────────────────────

<#
.SYNOPSIS
Turns whatever a step script emitted into one StepResult.

.DESCRIPTION
The last StepResult in the output wins. Scripts not yet rewritten (todo.md
Phase 5) return hashtables with lowercase ad-hoc statuses; those are mapped
here. Remove the legacy branch once no script returns a hashtable.

Output that is neither (leaked native output, New-Item objects) is ignored.
#>
function ConvertTo-StepResult {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyCollection()][object[]]$Output)

    $items = @($Output | Where-Object { $null -ne $_ })

    $stepResult = $items | Where-Object { $_.PSObject.TypeNames -like '*Dotconfigs.StepResult' } | Select-Object -Last 1
    if ($stepResult) { return $stepResult }

    $legacy = $items | Where-Object { $_ -is [hashtable] -and $_.ContainsKey('status') } | Select-Object -Last 1
    if (-not $legacy) {
        return New-StepResult Failed 'The step returned no result (it may have exited early or failed to start).'
    }

    $message = [string]$legacy['message']
    $data = @{ LegacyStatus = $legacy.status }
    if ($legacy['restart_required'] -eq $true) {
        return New-StepResult RestartRequired ($message ? $message : 'A restart is required.') -Data $data
    }
    if ($legacy['restart_recommended'] -eq $true) { $data.RestartRecommended = $true }

    $status = switch ($legacy.status) {
        { $_ -in 'success', 'installed' } { 'Success' }
        { $_ -in 'skipped', 'already_installed', 'features_ready' } { 'Skipped' }
        'partial' { 'Partial' }
        { $_ -in 'error', 'failed' } { 'Failed' }
        default { $null }
    }
    if (-not $status) {
        return New-StepResult Failed "Unknown legacy status '$($legacy.status)'. $message".Trim() -Data $data
    }
    return New-StepResult $status $message -Data $data
}

<#
.SYNOPSIS
Wraps a step and its result for reporting and serialization.
#>
function New-StepOutcome {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object only.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Step,
        [Parameter(Mandatory)]$Result,
        [timespan]$Duration = [timespan]::Zero
    )

    [pscustomobject]@{
        PSTypeName  = 'Dotconfigs.StepOutcome'
        Step        = $Step.Name
        Description = $Step.Description
        Admin       = $Step.Admin
        Critical    = $Step.Critical
        Result      = $Result
        Duration    = $Duration
    }
}

<#
.SYNOPSIS
Process exit code for a run: 1 on any failure, 3010 for a pending restart, else 0.
#>
function Get-RunExitCode {
    [CmdletBinding()]
    [OutputType([int])]
    param([AllowEmptyCollection()][object[]]$Outcomes = @())

    if (@($Outcomes | Where-Object { Test-StepFailed $_.Result }).Count -gt 0) { return 1 }
    if (@($Outcomes | Where-Object { $_.Result.Status -eq 'RestartRequired' }).Count -gt 0) { return 3010 }
    return 0
}

# ── Running steps ───────────────────────────────────────────────────────────

<#
.SYNOPSIS
Runs one step script and returns its StepOutcome. Never throws.

.PARAMETER ScriptRoot
Directory the step's Script path is relative to.
#>
function Invoke-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Step,
        [Parameter(Mandatory)][string]$ScriptRoot
    )

    Write-StepHeader $Step.Description
    $scriptPath = Join-Path $ScriptRoot $Step.Script
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        return New-StepOutcome -Step $Step -Result (New-StepResult Failed "Script not found: $scriptPath")
    }

    # Tools installed by earlier steps (or the elevated batch) must be visible.
    Update-SessionPath

    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $parameters = $Step.Parameters
        $output = & {
            # Legacy scripts were written for the default error behaviour and no
            # strict mode; rewritten scripts set both themselves.
            Set-StrictMode -Off
            $ErrorActionPreference = 'Continue'
            & $scriptPath @parameters
        }
        $result = ConvertTo-StepResult $output
    } catch {
        $result = New-StepResult Failed $_.Exception.Message
    }
    $timer.Stop()

    $outcome = New-StepOutcome -Step $Step -Result $result -Duration $timer.Elapsed
    Write-StepOutcome $outcome
    return $outcome
}

<#
.SYNOPSIS
Runs steps in order in this process.

.DESCRIPTION
Stops after a step that needs a restart (later steps may depend on it) or after
a failed Critical step.

.OUTPUTS
Object with Outcomes, StopReason ($null, 'RestartRequired' or 'CriticalFailure')
and LogPath ($null here; set by the elevated runner).
#>
function Invoke-StepBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Steps,
        [Parameter(Mandatory)][string]$ScriptRoot
    )

    $outcomes = [Collections.Generic.List[object]]::new()
    $stopReason = $null
    foreach ($step in $Steps) {
        $outcome = Invoke-Step -Step $step -ScriptRoot $ScriptRoot
        $outcomes.Add($outcome)
        if ($outcome.Result.Status -eq 'RestartRequired') { $stopReason = 'RestartRequired'; break }
        if ($step.Critical -and (Test-StepFailed $outcome.Result)) { $stopReason = 'CriticalFailure'; break }
    }

    [pscustomobject]@{ Outcomes = $outcomes.ToArray(); StopReason = $stopReason; LogPath = $null }
}

<#
.SYNOPSIS
Runs steps in one elevated child process and returns its batch result.

.DESCRIPTION
Starts this same pwsh executable with -Verb RunAs on Invoke-ElevatedSteps.ps1.
The child re-reads the step table, checks it runs as the same user (so links
and HKCU writes cannot land in another account's profile), runs the steps and
writes the batch result as CliXml for this process to read back.

Declined elevation, or a child that dies without writing results, turns every
requested step into a Failed outcome.
#>
function Invoke-ElevatedStepBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Steps,
        [Parameter(Mandatory)][string]$StepTablePath,
        [Parameter(Mandatory)][string]$LogDirectory
    )

    $workDir = New-WorkDirectory -Prefix 'dotconfigs-elevated'
    $resultPath = Join-Path $workDir 'result.clixml'

    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Invoke-ElevatedSteps.ps1'),
        '-StepTablePath', $StepTablePath,
        '-StepNames', ($Steps.Name -join ','),
        '-ResultPath', $resultPath,
        '-ExpectedUserSid', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value,
        '-LogDirectory', $LogDirectory
    )
    $commandLine = ($arguments | ForEach-Object { ConvertTo-CommandLineArgument $_ }) -join ' '

    function Get-FailedBatch([string]$Message) {
        [pscustomobject]@{
            Outcomes   = @($Steps | ForEach-Object { New-StepOutcome -Step $_ -Result (New-StepResult Failed $Message) })
            StopReason = $null
            LogPath    = $null
        }
    }

    try {
        Write-Action "Requesting Administrator rights for: $($Steps.Name -join ', ')"
        Write-Info 'The elevated steps run in a new window; this window waits for it.'
        try {
            $process = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $commandLine `
                -Verb RunAs -Wait -PassThru
        } catch {
            return Get-FailedBatch "Elevation was declined or failed: $($_.Exception.Message)"
        }

        if (-not (Test-Path -LiteralPath $resultPath)) {
            return Get-FailedBatch "The elevated process exited with $($process.ExitCode) without reporting results."
        }
        $batch = Import-Clixml -LiteralPath $resultPath
        foreach ($outcome in $batch.Outcomes) { Write-StepOutcome $outcome }
        return $batch
    } finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue # safe: private temp dir from New-WorkDirectory
    }
}

# ── Reporting ───────────────────────────────────────────────────────────────

$script:StatusColors = @{
    Success         = 'Green'
    Skipped         = 'Cyan'
    RestartRequired = 'Yellow'
    Partial         = 'Red'
    Failed          = 'Red'
}

<#
.SYNOPSIS
Prints one line for a finished step.
#>
function Write-StepOutcome {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Outcome)

    $status = $Outcome.Result.Status
    $color = $script:StatusColors[$status] ?? 'Red'
    $line = '[{0}] {1} ({2:mm\:ss})' -f $status, $Outcome.Step, $Outcome.Duration
    if ($Outcome.Result.Message) { $line += ": $($Outcome.Result.Message)" }
    Write-Host $line -ForegroundColor $color
}

<#
.SYNOPSIS
Prints the steps a run would execute, grouped by privilege.
#>
function Write-StepPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Batches)

    Write-StepHeader 'Plan'
    if ($Batches.Count -eq 0) {
        Write-Host 'No steps selected.' -ForegroundColor Yellow
        return
    }
    $index = 0
    foreach ($batch in $Batches) {
        $runsAs = if ($batch.Elevate) { 'elevated (one UAC prompt)' } else { 'this process' }
        Write-Host "  Runs in $runsAs`:" -ForegroundColor Gray
        foreach ($step in $batch.Steps) {
            $index++
            Write-Host ('    {0,2}. {1,-16} {2}' -f $index, $step.Name, $step.Description)
        }
    }
}

<#
.SYNOPSIS
Prints the end-of-run summary.

.PARAMETER NotRun
Selected steps that never ran because the run stopped early.
#>
function Write-RunSummary {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Outcomes = @(),
        [AllowEmptyCollection()][object[]]$NotRun = @(),
        [AllowEmptyCollection()][string[]]$LogPaths = @()
    )

    Write-StepHeader 'Summary'
    foreach ($outcome in $Outcomes) { Write-StepOutcome $outcome }
    foreach ($step in $NotRun) {
        Write-Host "[NotRun] $($step.Name)" -ForegroundColor DarkGray
    }

    $recommended = @($Outcomes | Where-Object {
            $_.Result.Data -is [Collections.IDictionary] -and $_.Result.Data['RestartRecommended'] -eq $true
        })
    if ($recommended) {
        Write-Host "A restart is recommended after: $($recommended.Step -join ', ')." -ForegroundColor Yellow
    }
    foreach ($log in $LogPaths | Where-Object { $_ }) {
        Write-Info "Log: $log"
    }
}

Export-ModuleMember -Function @(
    'Import-StepTable', 'Select-Step', 'Split-StepBatch',
    'ConvertTo-StepResult', 'New-StepOutcome', 'Get-RunExitCode',
    'Invoke-Step', 'Invoke-StepBatch', 'Invoke-ElevatedStepBatch',
    'Write-StepOutcome', 'Write-StepPlan', 'Write-RunSummary'
)
