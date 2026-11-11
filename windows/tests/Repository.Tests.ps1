#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Repository-wide checks: every PowerShell file parses and follows the
conventions in windows/README.md (Development).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeDiscovery/BeforeAll are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot 'TestSupport.psm1') -Force

    $root = Get-RepoRoot

    $allFiles = Get-PowerShellFile | ForEach-Object {
        @{ Name = $_; Path = Join-Path $root $_ }
    }
    # Scripts and modules; .psd1 data files have no #Requires header.
    $codeFiles = $allFiles | Where-Object { $_.Name -match '\.ps(m)?1$' }

    $bootstrap = @{ Path = Join-Path $root 'windows\Bootstrap.ps1' }
    $hasWindowsPowerShell = [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue)
    $hasAnalyzer = [bool](Get-Module -ListAvailable PSScriptAnalyzer)

    $manifests = 'windows/github-packages.jsonc', 'windows/packages.jsonc', 'vs/vsconfig.jsonc', 'vs/extensions.jsonc' |
        ForEach-Object { @{ Name = $_; Path = Join-Path $root $_ } }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestSupport.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\lib\Common.psm1') -Force
}


Describe '<Name>' -ForEach $allFiles {
    It 'parses without errors in PowerShell 7' {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'has no shebang line' {
        (Get-Content -LiteralPath $Path -TotalCount 1) | Should -Not -Match '^#!'
    }
}

Describe '<Name> conventions' -ForEach $codeFiles {
    BeforeAll {
        $text = Get-Content -LiteralPath $Path -Raw
    }

    It 'requires PowerShell 7' -Skip:($Name -eq 'windows/Bootstrap.ps1') {
        $text | Should -Match '(?m)^#Requires -Version 7'
    }

    It 'never writes PATH through [Environment]::SetEnvironmentVariable' {
        # It flattens REG_EXPAND_SZ and expands %VARS%; use Add-PathEntry / Remove-PathEntry.
        $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
        $offending = $ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
                "$($node.Member)" -eq 'SetEnvironmentVariable' -and
                $node.Arguments.Count -gt 0 -and
                $node.Arguments[0] -is [Management.Automation.Language.StringConstantExpressionAst] -and
                $node.Arguments[0].Value -eq 'Path'
            }, $true) |
            ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Extent.Text)" }
        $offending | Should -BeNullOrEmpty
    }

    It 'never removes a path recursively without a guard against links' {
        # Remove-Item -Recurse follows junctions on Windows PowerShell 5.1. Rewritten
        # scripts use Remove-LinkOnly for links; a recursive delete must name the
        # reason on the same line with a '# safe:' comment.
        $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
        $lines = $text -split '\r?\n'
        $offending = $ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -in 'Remove-Item', 'rm', 'del', 'rmdir', 'ri' -and
                ($node.CommandElements | Where-Object {
                    $_ -is [Management.Automation.Language.CommandParameterAst] -and
                    $_.ParameterName -like 'r*' -and 'recurse'.StartsWith($_.ParameterName.ToLowerInvariant())
                })
            }, $true) |
            Where-Object { $lines[$_.Extent.EndLineNumber - 1] -notmatch '#\s*safe:' } |
            ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Extent.Text)" }
        $offending | Should -BeNullOrEmpty
    }
}

Describe 'Bootstrap.ps1 (runs on Windows PowerShell 5.1)' {
    It 'parses under Windows PowerShell 5.1' -Skip:(-not $hasWindowsPowerShell) -TestCases @($bootstrap) {
        # -Command takes the rest of the line as code, so the path is embedded as a literal.
        $literal = "'" + ($Path -replace "'", "''") + "'"
        $command = '$e = $null; [void][Management.Automation.Language.Parser]::ParseFile(' + $literal +
            ', [ref]$null, [ref]$e); $e.Count'
        $count = & powershell.exe -NoProfile -NonInteractive -Command $command
        $LASTEXITCODE | Should -Be 0
        [int]($count | Select-Object -Last 1) | Should -Be 0
    }

    It 'uses only syntax and commands that exist in 5.1' -Skip:(-not $hasAnalyzer) -TestCases @($bootstrap) {
        $settings = @{
            IncludeRules = @('PSUseCompatibleSyntax', 'PSUseCompatibleCommands')
            Rules        = @{
                PSUseCompatibleSyntax   = @{ Enable = $true; TargetVersions = @('5.1') }
                PSUseCompatibleCommands = @{
                    Enable         = $true
                    TargetProfiles = @('win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
                }
            }
        }
        $findings = Invoke-ScriptAnalyzer -Path $Path -Settings $settings |
            ForEach-Object { "line $($_.Line): $($_.Message)" }
        $findings | Should -BeNullOrEmpty
    }

    It 'is ASCII-only, since 5.1 reads BOM-less files as Windows-1252' -TestCases @($bootstrap) {
        $bytes = [IO.File]::ReadAllBytes($Path)
        @($bytes | Where-Object { $_ -gt 0x7F }).Count | Should -Be 0
    }
}

Describe 'Manifest <Name>' -ForEach $manifests {
    It 'parses with Read-Jsonc' {
        { Read-Jsonc $Path } | Should -Not -Throw
    }
}
