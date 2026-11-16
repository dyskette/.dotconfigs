#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Tests for tmux/scripts/Psmux.psm1 and the theme files it parses.

.NOTES
psmux itself is never called: Invoke-PsmuxCommand is mocked inside the module,
so the running psmux server is not touched.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeAll/BeforeEach are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeAll {
    $tmuxDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\tmux')).Path
    Import-Module (Join-Path $tmuxDir 'scripts\Psmux.psm1') -Force
}

AfterAll {
    Remove-Module Psmux -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-ThemeLine' {
    It 'parses <Line>' -TestCases @(
        @{ Line = 'set -g status-style "bg=#2d353b,fg=#d3c6aa"'; Option = 'status-style'; Value = 'bg=#2d353b,fg=#d3c6aa' }
        @{ Line = '  set-option -g mode-style bg=red'; Option = 'mode-style'; Value = 'bg=red' }
        @{ Line = 'set -gq popup-border-style "fg=#7fbbb3"'; Option = 'popup-border-style'; Value = 'fg=#7fbbb3' }
        @{ Line = 'set -g status-left ""'; Option = 'status-left'; Value = '' }
    ) {
        $setting = ConvertFrom-ThemeLine $Line
        $setting.Option | Should -Be $Option
        $setting.Value | Should -Be $Value
    }

    It 'ignores <Line>' -TestCases @(
        @{ Line = '# comment' }, @{ Line = '' }, @{ Line = 'bind-key r source-file x' }, @{ Line = 'set status on' }
    ) {
        ConvertFrom-ThemeLine $Line | Should -BeNullOrEmpty
    }

    It 'parses every non-comment line of the theme files used by set-theme.ps1' {
        foreach ($theme in 'everforest-dark-medium', 'everforest-light-medium') {
            $lines = Get-Content (Join-Path $tmuxDir "$theme.conf") | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' }
            foreach ($line in $lines) {
                ConvertFrom-ThemeLine $line | Should -Not -BeNullOrEmpty -Because "$theme.conf: $line"
            }
        }
    }
}

Describe 'Invoke-PsmuxCommand' {
    It 'fails clearly when psmux is not installed' {
        Mock Get-Command -ModuleName Psmux { $null } -ParameterFilter { $Name -eq 'psmux' }
        { Invoke-PsmuxCommand -Arguments @('ls') } | Should -Throw '*psmux.exe is not on PATH*'
    }
}
