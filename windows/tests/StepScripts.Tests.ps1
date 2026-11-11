#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Tests for the rewritten step scripts in windows/.

.NOTES
Every installer call (winget, vswhere, setup.exe, uv/cargo/go) is mocked. The
scripts run from this file's session state, so plain Mocks intercept them.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeAll/BeforeEach are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\Common.psm1') -Force
    $windowsDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    function Invoke-StepScript([string]$Name, [hashtable]$Parameters = @{}) {
        $output = @(& (Join-Path $windowsDir $Name) @Parameters)
        # The contract: exactly one object, and it is a StepResult.
        $output | Should -HaveCount 1 -Because "$Name must return only its StepResult"
        $output[0].PSObject.TypeNames | Should -Contain 'Dotconfigs.StepResult'
        $output[0]
    }
}

Describe 'Install-WingetPackages.ps1' {
    BeforeEach {
        $manifest = Join-Path $TestDrive 'packages.jsonc'
        Set-Content $manifest '{}'
        Mock Get-Command { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }
    }

    It 'succeeds when winget import exits 0, retrying any failure' {
        Mock Invoke-Winget { 0 }
        (Invoke-StepScript 'Install-WingetPackages.ps1' @{ ManifestPath = $manifest }).Status | Should -Be 'Success'
        Should -Invoke Invoke-Winget -Times 1 -Exactly -ParameterFilter {
            $RetryOnAnyExitCode -and $Arguments[0] -eq 'import' -and $Arguments -contains $manifest
        }
    }

    It 'reports Partial with the exit code when packages failed' {
        Mock Invoke-Winget { -1978335189 }
        $result = Invoke-StepScript 'Install-WingetPackages.ps1' @{ ManifestPath = $manifest }
        $result.Status | Should -Be 'Partial'
        $result.Message | Should -BeLike '*0x8A15002B*'
    }

    It 'fails without a manifest or without winget' {
        (Invoke-StepScript 'Install-WingetPackages.ps1' @{ ManifestPath = (Join-Path $TestDrive 'none.jsonc') }).Message |
            Should -BeLike '*not found*'
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }
        (Invoke-StepScript 'Install-WingetPackages.ps1' @{ ManifestPath = $manifest }).Message |
            Should -BeLike '*not on PATH*'
    }
}

Describe 'Install-LanguageTools.ps1' {
    BeforeEach {
        $manifest = Join-Path $TestDrive 'tools.jsonc'
        Mock Get-Command { [pscustomobject]@{ Name = $Name } } -ParameterFilter { $Name -in 'uv', 'cargo', 'go' }
        Mock Invoke-Native { [pscustomobject]@{ ExitCode = 0; Output = @(); Succeeded = $true } }
    }

    It 'installs every listed tool with the right command' {
        Set-Content $manifest '{ "uv": ["poetry"], "go": ["example.com/tool@latest"] }'
        $result = Invoke-StepScript 'Install-LanguageTools.ps1' @{ ManifestPath = $manifest }
        $result.Status | Should -Be 'Success'
        $result.Data.Installed | Should -Be @('poetry', 'example.com/tool@latest')
        Should -Invoke Invoke-Native -ParameterFilter { $FilePath -eq 'uv' -and ($Arguments -join ' ') -eq 'tool install poetry' }
        Should -Invoke Invoke-Native -ParameterFilter { $FilePath -eq 'go' -and ($Arguments -join ' ') -eq 'install example.com/tool@latest' }
    }

    It 'reports Partial when some tools fail' {
        Set-Content $manifest '{ "uv": ["good", "bad"] }'
        Mock Invoke-Native { [pscustomobject]@{ ExitCode = 2; Output = @(); Succeeded = $false } } -ParameterFilter { $Arguments -contains 'bad' }
        $result = Invoke-StepScript 'Install-LanguageTools.ps1' @{ ManifestPath = $manifest }
        $result.Status | Should -Be 'Partial'
        $result.Message | Should -BeLike '*bad (exit 2)*'
    }

    It 'fails the tools of a toolchain that is not on PATH' {
        Set-Content $manifest '{ "cargo": ["tree-sitter-cli"] }'
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'cargo' }
        $result = Invoke-StepScript 'Install-LanguageTools.ps1' @{ ManifestPath = $manifest }
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*cargo not on PATH*'
    }

    It 'restores the environment after cargo' {
        Set-Content $manifest '{ "cargo": ["tree-sitter-cli"] }'
        $before = @{ Path = $env:Path; LIBCLANG_PATH = $env:LIBCLANG_PATH; INCLUDE = $env:INCLUDE }
        Invoke-StepScript 'Install-LanguageTools.ps1' @{ ManifestPath = $manifest } | Out-Null
        $env:Path | Should -Be $before.Path
        $env:LIBCLANG_PATH | Should -Be $before.LIBCLANG_PATH
        $env:INCLUDE | Should -Be $before.INCLUDE
    }

    It 'skips when nothing is listed' {
        Set-Content $manifest '{ "uv": [] }'
        (Invoke-StepScript 'Install-LanguageTools.ps1' @{ ManifestPath = $manifest }).Status | Should -Be 'Skipped'
    }

    It 'reads the real language-tools.jsonc' {
        { Read-Jsonc (Join-Path $windowsDir 'language-tools.jsonc') } | Should -Not -Throw
    }
}

Describe 'Install-VisualStudio.ps1' {
    BeforeEach {
        $config = Join-Path $TestDrive 'vsconfig.jsonc'
        Set-Content $config '{ // comment
  "version": "1.0", "components": ["A.Component", "B.Component"] }'
        $parameters = @{
            Product = 'Microsoft.VisualStudio.Product.Enterprise'; WingetId = 'Microsoft.VisualStudio.Enterprise'
            VersionRange = '[18.0,19.0)'; ConfigPath = $config
        }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*vswhere.exe' }
        Mock Invoke-Winget { 0 }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
    }

    It 'skips when the installation already has every component' {
        Mock Invoke-Native { [pscustomobject]@{ Output = @('C:\VS'); Succeeded = $true; ExitCode = 0 } }
        (Invoke-StepScript 'Install-VisualStudio.ps1' $parameters).Status | Should -Be 'Skipped'
        Should -Invoke Invoke-Native -ParameterFilter { $Arguments -contains '-requires' -and $Arguments -contains 'B.Component' }
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Invoke-Winget -Times 0 -Exactly
    }

    It 'modifies an incomplete installation and recommends a restart on 3010' {
        Mock Invoke-Native { [pscustomobject]@{ Output = @('C:\Program Files\VS'); Succeeded = $true; ExitCode = 0 } } -ParameterFilter { $Arguments -notcontains '-requires' }
        Mock Invoke-Native { [pscustomobject]@{ Output = @(); Succeeded = $true; ExitCode = 0 } } -ParameterFilter { $Arguments -contains '-requires' }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 3010 } }

        $result = Invoke-StepScript 'Install-VisualStudio.ps1' $parameters
        $result.Status | Should -Be 'Success'
        $result.Data.RestartRecommended | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\setup.exe' -and $ArgumentList -like 'modify --installPath "C:\Program Files\VS" --config *--passive --norestart'
        }
    }

    It 'installs through winget when Visual Studio is absent' {
        Mock Invoke-Native { [pscustomobject]@{ Output = @(); Succeeded = $true; ExitCode = 0 } }
        (Invoke-StepScript 'Install-VisualStudio.ps1' $parameters).Status | Should -Be 'Success'
        Should -Invoke Invoke-Winget -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'Microsoft.VisualStudio.Enterprise' -and
            ($Arguments | Where-Object { $_ -like '--wait --passive --norestart --config *' })
        }
    }

    It 'fails with the exit code and log location on an installer error' {
        Mock Invoke-Native { [pscustomobject]@{ Output = @(); Succeeded = $true; ExitCode = 0 } }
        Mock Invoke-Winget { 1603 }
        $result = Invoke-StepScript 'Install-VisualStudio.ps1' $parameters
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*1603*dd_installer_*'
    }

    It 'fails when the configuration is missing' {
        $parameters.ConfigPath = Join-Path $TestDrive 'missing.jsonc'
        (Invoke-StepScript 'Install-VisualStudio.ps1' $parameters).Status | Should -Be 'Failed'
    }
}
