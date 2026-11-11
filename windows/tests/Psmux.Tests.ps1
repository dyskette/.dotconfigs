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

Describe 'ConvertTo-SessionName' {
    It 'turns <Path> into <Name>' -TestCases @(
        @{ Path = 'C:\Users\me\.dotconfigs'; Name = '_dotconfigs' }
        @{ Path = 'C:\Users\me\my project\'; Name = 'my_project' }
        @{ Path = 'C:/work/app.v2/'; Name = 'app_v2' }
    ) {
        ConvertTo-SessionName $Path | Should -Be $Name
    }
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

Describe 'Switch-ToDirectorySession' {
    It 'creates a missing session, then switches to it by exact name' {
        Mock Invoke-PsmuxCommand -ModuleName Psmux { $null } -ParameterFilter { $Arguments[0] -eq 'has-session' }
        Mock Invoke-PsmuxCommand -ModuleName Psmux { '' }

        Switch-ToDirectorySession -Path 'C:\src\dot' | Should -Be 'dot'

        Should -Invoke Invoke-PsmuxCommand -ModuleName Psmux -ParameterFilter { ($Arguments -join ' ') -eq 'has-session -t =dot' }
        Should -Invoke Invoke-PsmuxCommand -ModuleName Psmux -ParameterFilter { ($Arguments -join ' ') -eq 'new-session -d -s dot -c C:\src\dot' }
        Should -Invoke Invoke-PsmuxCommand -ModuleName Psmux -ParameterFilter { ($Arguments -join ' ') -eq 'switch-client -t =dot' }
    }

    It 'does not create a session that exists' {
        Mock Invoke-PsmuxCommand -ModuleName Psmux { '' }
        Switch-ToDirectorySession -Path 'C:\src\dot' | Out-Null
        Should -Invoke Invoke-PsmuxCommand -ModuleName Psmux -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'new-session' }
    }
}

Describe 'Select-HomeDirectory' {
    It 'explains which tool is missing' {
        Mock Get-Command -ModuleName Psmux { $null } -ParameterFilter { $Name -eq 'fzf' }
        Mock Get-Command -ModuleName Psmux { [pscustomobject]@{ Name = 'fd' } } -ParameterFilter { $Name -eq 'fd' }
        { Select-HomeDirectory -Header 'x' } | Should -Throw '*fzf is not on PATH*'
    }
}

Describe 'Invoke-PsmuxCommand' {
    It 'fails clearly when psmux is not installed' {
        Mock Get-Command -ModuleName Psmux { $null } -ParameterFilter { $Name -eq 'psmux' }
        { Invoke-PsmuxCommand -Arguments @('ls') } | Should -Throw '*psmux.exe is not on PATH*'
    }
}
