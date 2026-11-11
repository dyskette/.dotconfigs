#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Tests for the user-level step scripts: Node LTS, Windows settings, font and
OpenCode.

.NOTES
No real installer runs and no real setting changes: fnm, GitHub, downloads,
version records and broadcasts are mocked, registry writes go to
HKCU\Software\DotconfigsTests, and files go to $TestDrive.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeAll/BeforeEach are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\Common.psm1') -Force
    $windowsDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $testKey = 'HKCU:\Software\DotconfigsTests'

    function Invoke-StepScript([string]$Name, [hashtable]$Parameters = @{}) {
        $output = @(& (Join-Path $windowsDir $Name) @Parameters)
        $output | Should -HaveCount 1 -Because "$Name must return only its StepResult"
        $output[0].PSObject.TypeNames | Should -Contain 'Dotconfigs.StepResult'
        $output[0]
    }

    function Get-NativeResult([string[]]$Output = @(), [int]$ExitCode = 0) {
        [pscustomobject]@{ Output = $Output; ExitCode = $ExitCode; Succeeded = $ExitCode -eq 0 }
    }
}

AfterAll {
    Remove-Item -Path $testKey -Recurse -Force -ErrorAction SilentlyContinue # safe: scratch registry key of these tests
}

Describe 'Setup-NodeLTS.ps1' {
    BeforeEach {
        Mock Get-Command { [pscustomobject]@{ Name = 'fnm' } } -ParameterFilter { $Name -eq 'fnm' }
        Mock Invoke-Native { Get-NativeResult @('v26.13.1 (Lithium)') } -ParameterFilter { $Arguments[0] -eq 'ls-remote' }
        Mock Invoke-Native { Get-NativeResult @('* v24.14.1', '* v26.13.0 default, lts-latest', '* system') } -ParameterFilter { $Arguments[0] -eq 'list' }
        Mock Invoke-Native { Get-NativeResult } -ParameterFilter { $Arguments[0] -in 'install', 'default' }
        Mock Invoke-Native { Get-NativeResult @('v26.13.1') } -ParameterFilter { $Arguments[0] -eq 'exec' }
    }

    It 'installs a newer LTS and makes it the default' {
        $result = Invoke-StepScript 'Setup-NodeLTS.ps1'
        $result.Status | Should -Be 'Success'
        $result.Data.Previous | Should -Be 'v26.13.0'
        Should -Invoke Invoke-Native -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'install v26.13.1' }
        Should -Invoke Invoke-Native -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'default v26.13.1' }
    }

    It 'only switches the default when the LTS is installed but not default' {
        Mock Invoke-Native { Get-NativeResult @('* v26.13.1', '* v26.13.0 default') } -ParameterFilter { $Arguments[0] -eq 'list' }
        (Invoke-StepScript 'Setup-NodeLTS.ps1').Status | Should -Be 'Success'
        Should -Invoke Invoke-Native -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'install' }
        Should -Invoke Invoke-Native -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'default' }
    }

    It 'skips when the latest LTS is already the default' {
        Mock Invoke-Native { Get-NativeResult @('* v26.13.1 default, lts-latest') } -ParameterFilter { $Arguments[0] -eq 'list' }
        (Invoke-StepScript 'Setup-NodeLTS.ps1').Status | Should -Be 'Skipped'
        Should -Invoke Invoke-Native -Times 0 -Exactly -ParameterFilter { $Arguments[0] -in 'install', 'default' }
    }

    It 'fails without fnm' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'fnm' }
        (Invoke-StepScript 'Setup-NodeLTS.ps1').Message | Should -BeLike '*fnm is not on PATH*'
    }
}

Describe 'Configure-WindowsSettings.ps1' {
    BeforeEach {
        $key = "$testKey\Advanced-$([guid]::NewGuid().ToString('N'))"
        Mock Send-BroadcastMessage { $true }
    }

    It 'applies every setting, then skips on the next run' {
        $first = Invoke-StepScript 'Configure-WindowsSettings.ps1' @{ AdvancedKey = $key }
        $first.Status | Should -Be 'Success'
        $first.Data.Changed | Should -HaveCount 5
        (Get-Item $key).GetValue('HideFileExt') | Should -Be 0
        (Get-Item $key).GetValue('Hidden') | Should -Be 1
        (Get-Item $key).GetValueKind('Hidden') | Should -Be 'DWord'
        Should -Invoke Send-BroadcastMessage -Times 1 -Exactly

        (Invoke-StepScript 'Configure-WindowsSettings.ps1' @{ AdvancedKey = $key }).Status | Should -Be 'Skipped'
    }

    It 'changes only the values that differ' {
        Invoke-StepScript 'Configure-WindowsSettings.ps1' @{ AdvancedKey = $key } | Out-Null
        Set-ItemProperty -Path $key -Name Hidden -Value 2
        $result = Invoke-StepScript 'Configure-WindowsSettings.ps1' @{ AdvancedKey = $key }
        $result.Data.Changed | Should -Be @('Show hidden files')
    }

    It 'reports Partial when a value cannot be written' {
        Mock Set-ItemProperty { throw 'Access denied' } -ParameterFilter { $Name -eq 'Hidden' }
        $result = Invoke-StepScript 'Configure-WindowsSettings.ps1' @{ AdvancedKey = $key }
        $result.Status | Should -Be 'Partial'
        $result.Message | Should -BeLike '*Show hidden files*Access denied*'
    }

    It 'writes nothing under -WhatIf' {
        Invoke-StepScript 'Configure-WindowsSettings.ps1' @{ AdvancedKey = $key; WhatIf = $true } | Out-Null
        Test-Path $key | Should -BeFalse
    }
}

Describe 'Install-JetBrainsFont.ps1' {
    BeforeAll {
        # A release archive holding two NL styles and one style that is not installed.
        $fixture = Join-Path $TestDrive 'font-fixture'
        New-Item -ItemType Directory -Path $fixture | Out-Null
        'Regular', 'Bold' | ForEach-Object { Set-Content (Join-Path $fixture "JetBrainsMonoNLNerdFont-$_.ttf") "font $_" }
        Set-Content (Join-Path $fixture 'JetBrainsMonoNerdFont-Regular.ttf') 'not NL'
        $fontZip = Join-Path $TestDrive 'JetBrainsMono.zip'
        Compress-Archive -Path (Join-Path $fixture '*') -DestinationPath $fontZip

        $release = [pscustomobject]@{
            tag_name = 'v3.5.1'
            assets   = @([pscustomobject]@{ name = 'JetBrainsMono.zip'; browser_download_url = 'https://example.invalid/f.zip' })
        }
    }

    BeforeEach {
        $fonts = Join-Path $TestDrive "fonts-$([guid]::NewGuid().ToString('N'))"
        $registry = "$testKey\Fonts-$([guid]::NewGuid().ToString('N'))"
        $parameters = @{ FontDirectory = $fonts; RegistryPath = $registry }

        Mock Get-GitHubRelease { $release }
        Mock Get-ReleaseAssetHash { 'a' * 64 }
        Mock Invoke-Download { Copy-Item -LiteralPath $fontZip -Destination $OutFile; $OutFile }
        Mock Get-InstalledVersion { $null }
        Mock Set-InstalledVersion { }
        Mock Send-BroadcastMessage { $true }
    }

    It 'installs versioned files, registers them and records a verified install' {
        $result = Invoke-StepScript 'Install-JetBrainsFont.ps1' $parameters
        $result.Status | Should -Be 'Success'
        Join-Path $fonts 'JetBrainsMonoNLNerdFont-Regular_v3.5.1.ttf' | Should -Exist
        Join-Path $fonts 'JetBrainsMonoNerdFont-Regular_v3.5.1.ttf' | Should -Not -Exist
        (Get-Item $registry).GetValue('JetBrainsMonoNLNerdFont-Bold (TrueType)') |
            Should -Be (Join-Path $fonts 'JetBrainsMonoNLNerdFont-Bold_v3.5.1.ttf')
        Should -Invoke Invoke-Download -ParameterFilter { $Sha256 -eq ('a' * 64) }
        Should -Invoke Set-InstalledVersion -ParameterFilter { $Version -eq 'v3.5.1' -and $Verified }
        Should -Invoke Send-BroadcastMessage -ParameterFilter { $Message -eq 0x1D }
    }

    It 'upgrades: repoints the registry, drops stale styles and removes old files' {
        New-Item -ItemType Directory -Path $fonts | Out-Null
        New-Item -Path $registry -Force | Out-Null
        $old = Join-Path $fonts 'JetBrainsMonoNLNerdFont-Regular.ttf'
        Set-Content $old 'old'
        Set-ItemProperty -Path $registry -Name 'JetBrainsMonoNLNerdFont-Regular (TrueType)' -Value $old
        Set-ItemProperty -Path $registry -Name 'JetBrainsMonoNLNerdFont-Thin (TrueType)' -Value (Join-Path $fonts 'gone.ttf')
        Set-ItemProperty -Path $registry -Name 'Other Font (TrueType)' -Value 'C:\keep.ttf'
        Mock Get-InstalledVersion { [pscustomobject]@{ version = 'v3.4.0' } }

        $result = Invoke-StepScript 'Install-JetBrainsFont.ps1' $parameters
        $result.Data.Previous | Should -Be 'v3.4.0'
        $old | Should -Not -Exist
        $names = (Get-Item $registry).GetValueNames()
        $names | Should -Not -Contain 'JetBrainsMonoNLNerdFont-Thin (TrueType)'
        $names | Should -Contain 'Other Font (TrueType)'
        (Get-Item $registry).GetValue('JetBrainsMonoNLNerdFont-Regular (TrueType)') | Should -BeLike '*_v3.5.1.ttf'
    }

    It 'leaves an old file that is in use and says so' {
        New-Item -ItemType Directory -Path $fonts | Out-Null
        $old = Join-Path $fonts 'JetBrainsMonoNLNerdFont-Regular.ttf'
        Set-Content $old 'old'
        $lock = [IO.File]::Open($old, 'Open', 'Read', 'None')
        try {
            $result = Invoke-StepScript 'Install-JetBrainsFont.ps1' $parameters
        } finally {
            $lock.Dispose()
        }
        $result.Status | Should -Be 'Success'
        $result.Data.OldFilesInUse | Should -Be 1
        $result.Message | Should -BeLike '*in use*'
    }

    It 'skips when the recorded version is current and every file is present' {
        Invoke-StepScript 'Install-JetBrainsFont.ps1' $parameters | Out-Null
        Mock Get-InstalledVersion { [pscustomobject]@{ version = 'v3.5.1' } }
        (Invoke-StepScript 'Install-JetBrainsFont.ps1' $parameters).Status | Should -Be 'Skipped'
        Should -Invoke Invoke-Download -Times 1 -Exactly
    }

    It 'installs unverified, and records it so, when the release has no checksum' {
        Mock Get-ReleaseAssetHash { $null }
        $result = Invoke-StepScript 'Install-JetBrainsFont.ps1' $parameters 3>$null
        $result.Data.Verified | Should -BeFalse
        Should -Invoke Set-InstalledVersion -ParameterFilter { -not $Verified -and $Checksum -eq '' }
    }

    It 'fails when the archive has no matching fonts' {
        (Invoke-StepScript 'Install-JetBrainsFont.ps1' ($parameters + @{ FontPrefix = 'Missing-' })).Status | Should -Be 'Failed'
    }
}

Describe 'Install-OpenCode.ps1' {
    BeforeAll {
        # A fake opencode.exe whose content is its version; the --version mock reads it.
        function Build-OpenCodeZip([string]$Version) {
            $dir = Join-Path $TestDrive "opencode-$Version"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content (Join-Path $dir 'opencode.exe') $Version
            $zip = Join-Path $TestDrive "opencode-$Version.zip"
            if (-not (Test-Path $zip)) { Compress-Archive -Path (Join-Path $dir 'opencode.exe') -DestinationPath $zip }
            $zip
        }
        $zip2 = Build-OpenCodeZip '2.0.0'
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $parameters = @{ InstallDirectory = (Join-Path $root 'opt\opencode'); BinDirectory = (Join-Path $root 'bin') }
        $env:DOTCONFIGS_TEST_ZIP = $zip2
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                version  = '2.0.0'
                metadata = [pscustomobject]@{ files = [pscustomobject]@{
                        'opencode-windows-x64.zip'   = [pscustomobject]@{ url = 'https://example.invalid/x64.zip'; sha256 = 'a' * 64 }
                        'opencode-windows-arm64.zip' = [pscustomobject]@{ url = 'https://example.invalid/arm64.zip'; sha256 = 'b' * 64 }
                    } }
            }
        }
        Mock Invoke-Download { Copy-Item -LiteralPath $env:DOTCONFIGS_TEST_ZIP -Destination $OutFile; $OutFile }
        Mock Invoke-Native { Get-NativeResult @("opencode v$((Get-Content -LiteralPath $FilePath -Raw).Trim())") } -ParameterFilter { $Arguments -contains '--version' }
    }

    AfterEach {
        Remove-Item Env:\DOTCONFIGS_TEST_ZIP -ErrorAction SilentlyContinue
    }

    It 'installs the verified release and puts it on the bin path' {
        $result = Invoke-StepScript 'Install-OpenCode.ps1' $parameters 3>$null
        $result.Status | Should -Be 'Success'
        Join-Path $parameters.InstallDirectory 'opencode.exe' | Should -Exist
        Get-Content (Join-Path $parameters.BinDirectory 'opencode.exe') | Should -Be '2.0.0'
        Should -Invoke Invoke-Download -ParameterFilter { $Sha256 -eq ('a' * 64) }
    }

    It 'skips when up to date, and repairs a stale bin copy' {
        Invoke-StepScript 'Install-OpenCode.ps1' $parameters 3>$null | Out-Null
        $binCopy = Join-Path $parameters.BinDirectory 'opencode.exe'
        if (-not (Test-IsLink $binCopy)) { Set-Content $binCopy 'stale' }

        $result = Invoke-StepScript 'Install-OpenCode.ps1' $parameters 3>$null
        $result.Status | Should -Be 'Skipped'
        Get-Content $binCopy | Should -Be '2.0.0'
        Should -Invoke Invoke-Download -Times 1 -Exactly
    }

    It 'upgrades an older install' {
        $env:DOTCONFIGS_TEST_ZIP = Build-OpenCodeZip '1.0.0'
        Mock Invoke-RestMethod { [pscustomobject]@{ version = '1.0.0'; metadata = [pscustomobject]@{ files = [pscustomobject]@{ 'opencode-windows-x64.zip' = [pscustomobject]@{ url = 'u'; sha256 = 'a' * 64 } } } } }
        Invoke-StepScript 'Install-OpenCode.ps1' $parameters 3>$null | Out-Null

        $env:DOTCONFIGS_TEST_ZIP = $zip2
        Mock Invoke-RestMethod { [pscustomobject]@{ version = '2.0.0'; metadata = [pscustomobject]@{ files = [pscustomobject]@{ 'opencode-windows-x64.zip' = [pscustomobject]@{ url = 'u'; sha256 = 'a' * 64 } } } } }
        $result = Invoke-StepScript 'Install-OpenCode.ps1' $parameters 3>$null
        $result.Status | Should -Be 'Success'
        $result.Data.Previous | Should -Be '1.0.0'
    }

    It 'keeps the old install when the download fails verification' {
        Invoke-StepScript 'Install-OpenCode.ps1' $parameters 3>$null | Out-Null
        Mock Invoke-RestMethod { [pscustomobject]@{ version = '3.0.0'; metadata = [pscustomobject]@{ files = [pscustomobject]@{ 'opencode-windows-x64.zip' = [pscustomobject]@{ url = 'u'; sha256 = 'a' * 64 } } } } }
        Mock Invoke-Download { throw [System.IO.InvalidDataException]::new('Checksum mismatch') }

        $result = Invoke-StepScript 'Install-OpenCode.ps1' $parameters
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*Checksum mismatch*'
        Get-Content (Join-Path $parameters.InstallDirectory 'opencode.exe') | Should -Be '2.0.0'
    }

    It 'keeps the old install when opencode.exe is in use' {
        Invoke-StepScript 'Install-OpenCode.ps1' $parameters 3>$null | Out-Null
        Mock Invoke-RestMethod { [pscustomobject]@{ version = '3.0.0'; metadata = [pscustomobject]@{ files = [pscustomobject]@{ 'opencode-windows-x64.zip' = [pscustomobject]@{ url = 'u'; sha256 = 'a' * 64 } } } } }
        $exe = Join-Path $parameters.InstallDirectory 'opencode.exe'
        # Like a running exe: readable, but not renamable or deletable.
        $lock = [IO.File]::Open($exe, 'Open', 'Read', 'Read')
        try {
            $result = Invoke-StepScript 'Install-OpenCode.ps1' $parameters
        } finally {
            $lock.Dispose()
        }
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*still running*'
        Get-Content $exe | Should -Be '2.0.0'
    }
}
