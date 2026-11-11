#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Tests for windows/lib/StepRunner.psm1, the elevated runner, the real step
table and the orchestrator's dry run.

.NOTES
Steps are fake scripts written to $TestDrive. Nothing is installed and nothing
asks for elevation: Start-Process is mocked wherever -Verb RunAs would run.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeAll/BeforeEach are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\Common.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\lib\StepRunner.psm1') -Force
    $windowsDir = Resolve-Path (Join-Path $PSScriptRoot '..')

    function Build-TestStep {
        param(
            [string]$Name,
            [string]$Body,
            [switch]$Admin,
            [switch]$Critical,
            [hashtable]$Parameters = @{}
        )
        Set-Content -Path (Join-Path $TestDrive "$Name.ps1") -Value $Body
        [pscustomobject]@{
            Name = $Name; Script = "$Name.ps1"; Description = "Test $Name"
            Admin = [bool]$Admin; Critical = [bool]$Critical; OptIn = $false
            Tags = [string[]]@(); Parameters = $Parameters
        }
    }

    $commonImport = "Import-Module '$(Join-Path $windowsDir 'lib\Common.psm1')'"
}

AfterAll {
    Remove-Module StepRunner, Common -ErrorAction SilentlyContinue
}

Describe 'Import-StepTable' {
    It 'applies defaults' {
        $path = Join-Path $TestDrive 'minimal.psd1'
        Set-Content $path "@{ Steps = @( @{ Name = 'A'; Script = 'a.ps1'; Description = 'A' } ) }"
        $step = Import-StepTable $path
        $step.Admin | Should -BeFalse
        $step.Critical | Should -BeFalse
        $step.OptIn | Should -BeFalse
        $step.Tags | Should -HaveCount 0
        $step.Parameters | Should -BeOfType [hashtable]
    }

    It 'rejects <Case>' -TestCases @(
        @{ Case = 'unknown keys';   Steps = "@{ Name = 'A'; Script = 'a.ps1'; Description = 'A'; Admim = `$true }"; Message = '*unknown keys*Admim*' }
        @{ Case = 'duplicate names'; Steps = "@{ Name = 'A'; Script = 'a.ps1'; Description = 'A' }, @{ Name = 'A'; Script = 'b.ps1'; Description = 'B' }"; Message = '*twice*' }
        @{ Case = 'a missing Script'; Steps = "@{ Name = 'A'; Description = 'A' }"; Message = '*no Script*' }
    ) {
        $path = Join-Path $TestDrive 'bad.psd1'
        Set-Content $path "@{ Steps = @( $Steps ) }"
        { Import-StepTable $path } | Should -Throw $Message
    }

    It 'loads the real steps.psd1, and every script it names exists' {
        $steps = @(Import-StepTable (Join-Path $windowsDir 'steps.psd1'))
        $steps.Count | Should -BeGreaterThan 0
        foreach ($step in $steps) {
            Join-Path $windowsDir $step.Script | Should -Exist -Because "step $($step.Name) runs it"
        }
    }

    It 'lists every Admin step before the first user step, so a run asks for elevation once' {
        $admin = @(Import-StepTable (Join-Path $windowsDir 'steps.psd1') | ForEach-Object Admin)
        $firstUser = [array]::IndexOf($admin, $false)
        if ($firstUser -ge 0) {
            $admin[$firstUser..($admin.Count - 1)] | Should -Not -Contain $true
        }
    }
}

Describe 'Select-Step' {
    BeforeAll {
        $table = @(
            [pscustomobject]@{ Name = 'A'; Tags = @('packages'); OptIn = $false }
            [pscustomobject]@{ Name = 'B'; Tags = @('config'); OptIn = $false }
            [pscustomobject]@{ Name = 'W'; Tags = @('wsl'); OptIn = $true }
            [pscustomobject]@{ Name = 'C'; Tags = @('packages'); OptIn = $false }
        )
    }

    It 'leaves out opt-in steps by default and keeps table order' {
        (Select-Step -Steps $table).Name | Should -Be @('A', 'B', 'C')
    }

    It 'adds opt-in steps by tag with -Include' {
        (Select-Step -Steps $table -Include wsl).Name | Should -Be @('A', 'B', 'W', 'C')
    }

    It 'skips by name and by tag' {
        (Select-Step -Steps $table -Skip B).Name | Should -Be @('A', 'C')
        (Select-Step -Steps $table -Skip packages).Name | Should -Be @('B')
    }

    It 'runs only the selected steps, including opt-in ones' {
        (Select-Step -Steps $table -Only packages, W).Name | Should -Be @('A', 'W', 'C')
    }

    It 'applies -Skip after -Only' {
        (Select-Step -Steps $table -Only packages -Skip C).Name | Should -Be @('A')
    }

    It 'throws on an unknown name or tag' {
        { Select-Step -Steps $table -Skip nope } | Should -Throw '*Unknown step or tag: nope*'
    }
}

Describe 'Split-StepBatch' {
    BeforeAll {
        $steps = 'a1:1', 'a2:1', 'u1:0', 'a3:1' | ForEach-Object {
            $name, $admin = $_ -split ':'
            [pscustomobject]@{ Name = $name; Admin = $admin -eq '1' }
        }
    }

    It 'groups consecutive steps by privilege' {
        $batches = @(Split-StepBatch -Steps $steps)
        $batches.Elevate | Should -Be @($true, $false, $true)
        $batches[0].Steps.Name | Should -Be @('a1', 'a2')
    }

    It 'runs everything in one in-process batch when already elevated' {
        $batches = @(Split-StepBatch -Steps $steps -IsElevated)
        $batches | Should -HaveCount 1
        $batches[0].Elevate | Should -BeFalse
        $batches[0].Steps | Should -HaveCount 4
    }

    It 'returns nothing for no steps' {
        Split-StepBatch -Steps @() | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-StepResult' {
    It 'passes a StepResult through' {
        (ConvertTo-StepResult @(New-StepResult Skipped 'x')).Status | Should -Be 'Skipped'
    }

    It 'takes the last StepResult and ignores leaked output' {
        $result = ConvertTo-StepResult @('noise', (New-StepResult Failed 'first'), [IO.DirectoryInfo]'C:\', (New-StepResult Success 'last'))
        $result.Message | Should -Be 'last'
    }

    It 'fails a result in the old hashtable shape' {
        (ConvertTo-StepResult @(@{ status = 'success'; message = 'm' })).Status | Should -Be 'Failed'
    }

    It 'fails when the step returned nothing' {
        (ConvertTo-StepResult $null).Status | Should -Be 'Failed'
        (ConvertTo-StepResult @('just text')).Status | Should -Be 'Failed'
    }
}

Describe 'Get-RunExitCode' {
    It 'is <Code> for <Statuses>' -TestCases @(
        @{ Statuses = @('Success', 'Skipped');           Code = 0 }
        @{ Statuses = @('Success', 'RestartRequired');   Code = 3010 }
        @{ Statuses = @('Partial', 'RestartRequired');   Code = 1 }
        @{ Statuses = @('Success', 'Failed');            Code = 1 }
        @{ Statuses = @();                               Code = 0 }
    ) {
        $outcomes = @($Statuses | ForEach-Object { [pscustomobject]@{ Result = New-StepResult $_ } })
        Get-RunExitCode -Outcomes $outcomes | Should -Be $Code
    }
}

Describe 'Invoke-Step' {
    It 'returns the StepResult of a rewritten step and passes parameters by name' {
        $step = Build-TestStep -Name 'modern' -Parameters @{ Who = 'tests' } -Body @"
param([string]`$Who)
$commonImport
New-StepResult Success "hello `$Who"
"@
        $outcome = Invoke-Step -Step $step -ScriptRoot $TestDrive
        $outcome.Step | Should -Be 'modern'
        $outcome.Result.Status | Should -Be 'Success'
        $outcome.Result.Message | Should -Be 'hello tests'
        $outcome.Duration | Should -BeOfType [timespan]
    }

    It 'turns a thrown error into Failed' {
        $step = Build-TestStep -Name 'throws' -Body "throw 'kaboom'"
        $outcome = Invoke-Step -Step $step -ScriptRoot $TestDrive
        $outcome.Result.Status | Should -Be 'Failed'
        $outcome.Result.Message | Should -BeLike '*kaboom*'
    }

    It 'fails a step whose script is missing' {
        $step = [pscustomobject]@{ Name = 'gone'; Script = 'gone.ps1'; Description = 'gone'; Admin = $false; Critical = $false; Parameters = @{} }
        (Invoke-Step -Step $step -ScriptRoot $TestDrive).Result.Message | Should -BeLike '*not found*'
    }

    It 'fails a step that exits early without a result' {
        $step = Build-TestStep -Name 'exits' -Body "Write-Warning 'needs admin'; exit 1"
        (Invoke-Step -Step $step -ScriptRoot $TestDrive).Result.Status | Should -Be 'Failed' 3>$null
    }

    It 'fails a step whose terminating error escapes it' {
        $step = Build-TestStep -Name 'strict' -Body @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
$commonImport
if (`$undefinedVariable) { 'unreachable' }
New-StepResult Success
"@
        $outcome = Invoke-Step -Step $step -ScriptRoot $TestDrive
        $outcome.Result.Status | Should -Be 'Failed'
        $outcome.Result.Message | Should -BeLike '*undefinedVariable*'
    }
}

Describe 'Invoke-StepBatch' {
    BeforeAll {
        $ok = Build-TestStep -Name 'ok' -Body "$commonImport; New-StepResult Success"
        $bad = Build-TestStep -Name 'bad' -Body "$commonImport; New-StepResult Failed 'broken'"
        $badCritical = Build-TestStep -Name 'badCritical' -Critical -Body "$commonImport; New-StepResult Failed 'broken'"
        $reboot = Build-TestStep -Name 'reboot' -Body "$commonImport; New-StepResult RestartRequired"
    }

    It 'continues after a non-critical failure' {
        $batch = Invoke-StepBatch -Steps @($bad, $ok) -ScriptRoot $TestDrive
        $batch.Outcomes.Step | Should -Be @('bad', 'ok')
        $batch.StopReason | Should -BeNullOrEmpty
    }

    It 'stops after a failed critical step' {
        $batch = Invoke-StepBatch -Steps @($ok, $badCritical, $ok) -ScriptRoot $TestDrive
        $batch.Outcomes.Step | Should -Be @('ok', 'badCritical')
        $batch.StopReason | Should -Be 'CriticalFailure'
    }

    It 'continues after a critical step that only partly failed' {
        $partialCritical = Build-TestStep -Name 'partialCritical' -Critical -Body "$commonImport; New-StepResult Partial 'update failed'"
        $batch = Invoke-StepBatch -Steps @($partialCritical, $ok) -ScriptRoot $TestDrive
        $batch.Outcomes.Step | Should -Be @('partialCritical', 'ok')
        $batch.StopReason | Should -BeNullOrEmpty
    }

    It 'stops after a step that needs a restart' {
        $batch = Invoke-StepBatch -Steps @($reboot, $ok) -ScriptRoot $TestDrive
        $batch.Outcomes.Step | Should -Be @('reboot')
        $batch.StopReason | Should -Be 'RestartRequired'
    }
}

Describe 'Invoke-ElevatedStepBatch' {
    BeforeAll {
        $steps = @(
            [pscustomobject]@{ Name = 'e1'; Description = 'e1'; Admin = $true; Critical = $false }
            [pscustomobject]@{ Name = 'e2'; Description = 'e2'; Admin = $true; Critical = $false }
        )
    }

    It 'fails every step when elevation is declined' {
        Mock Start-Process -ModuleName StepRunner { throw 'The operation was canceled by the user.' }
        $batch = Invoke-ElevatedStepBatch -Steps $steps -StepTablePath 'x.psd1' -LogDirectory $TestDrive
        $batch.Outcomes.Step | Should -Be @('e1', 'e2')
        $batch.Outcomes.Result.Status | Should -Be @('Failed', 'Failed')
        $batch.Outcomes[0].Result.Message | Should -BeLike '*declined*canceled by the user*'
    }

    It 'fails every step when the child writes no result' {
        Mock Start-Process -ModuleName StepRunner { [pscustomobject]@{ ExitCode = 7 } }
        $batch = Invoke-ElevatedStepBatch -Steps $steps -StepTablePath 'x.psd1' -LogDirectory $TestDrive
        $batch.Outcomes.Result.Status | Should -Be @('Failed', 'Failed')
        $batch.Outcomes[0].Result.Message | Should -BeLike '*exited with 7*'
    }

    It 'starts this pwsh elevated with quoted arguments' {
        Mock Start-Process -ModuleName StepRunner { [pscustomobject]@{ ExitCode = 0 } }
        Invoke-ElevatedStepBatch -Steps $steps -StepTablePath 'C:\with space\steps.psd1' -LogDirectory $TestDrive | Out-Null
        Should -Invoke Start-Process -ModuleName StepRunner -Times 1 -Exactly -ParameterFilter {
            $Verb -eq 'RunAs' -and $Wait -and
            $FilePath -eq (Get-Process -Id $PID).Path -and
            $ArgumentList -like '*-StepTablePath "C:\with space\steps.psd1"*' -and
            $ArgumentList -like '*-StepNames e1,e2*'
        }
    }
}

Describe 'Invoke-ElevatedSteps.ps1' {
    It 'refuses to run steps for a different user and still writes results' {
        $table = Join-Path $TestDrive 'elevated-table.psd1'
        Set-Content -Path (Join-Path $TestDrive 'never.ps1') -Value "Set-Content '$TestDrive\ran.txt' 'ran'"
        Set-Content $table "@{ Steps = @( @{ Name = 'never'; Script = 'never.ps1'; Description = 'never'; Admin = `$true } ) }"
        $resultPath = Join-Path $TestDrive 'result.clixml'

        & (Join-Path $windowsDir 'lib\Invoke-ElevatedSteps.ps1') -StepTablePath $table -StepNames 'never' `
            -ResultPath $resultPath -ExpectedUserSid 'S-1-5-21-0-0-0-1' -LogDirectory (Join-Path $TestDrive 'logs')

        $batch = Import-Clixml $resultPath
        $batch.Outcomes[0].Step | Should -Be 'never'
        $batch.Outcomes[0].Result.Message | Should -BeLike '*different user*'
        Test-StepFailed $batch.Outcomes[0].Result | Should -BeTrue -Because 'deserialized results must still be judged'
        $batch.LogPath | Should -Exist
        Join-Path $TestDrive 'ran.txt' | Should -Not -Exist
    }
}

Describe 'Install-WindowsEnvironment.ps1 dry run' {
    BeforeAll {
        $orchestrator = Join-Path $windowsDir 'Install-WindowsEnvironment.ps1'
        $pwsh = (Get-Process -Id $PID).Path
    }

    It 'prints the plan, runs nothing and exits 0 with -WhatIf' {
        $logs = Join-Path $TestDrive 'dry-run-logs'
        $output = & $pwsh -NoProfile -File $orchestrator -WhatIf -LogDirectory $logs *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'PackageManagers'
        $output | Should -Match 'What if'
        $logs | Should -Not -Exist
    }

    It 'maps the old -Skip switches onto steps' {
        $output = & $pwsh -NoProfile -File $orchestrator -WhatIf -SkipPackages -SkipFont *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Not -Match 'WingetPackages'
        $output | Should -Not -Match '\bFont\b'
        $output | Should -Match 'Dotfiles'
    }

    It 'exits 1 on an unknown step name' {
        $output = & $pwsh -NoProfile -File $orchestrator -WhatIf -Skip bogus *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $output | Should -Match 'Unknown step or tag: bogus'
    }
}
