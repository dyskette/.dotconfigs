#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Tests for the SQL*Plus, psql and winget setup steps.

.NOTES
Nothing is installed: Oracle, GitHub, winget, Appx and PATH changes are mocked,
files go to $TestDrive. State that changes during a run (the version after an
install) is carried through DOTCONFIGS_TEST_* environment variables, since
mocks run in the script's scope.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeAll/BeforeEach are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\Common.psm1') -Force
    $windowsDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    function Invoke-StepScript([string]$Name, [hashtable]$Parameters = @{}) {
        $output = @(& (Join-Path $windowsDir $Name) @Parameters)
        $output | Should -HaveCount 1 -Because "$Name must return only its StepResult"
        $output[0].PSObject.TypeNames | Should -Contain 'Dotconfigs.StepResult'
        $output[0]
    }

    function Get-NativeResult([string[]]$Output = @(), [int]$ExitCode = 0) {
        [pscustomobject]@{ Output = $Output; ExitCode = $ExitCode; Succeeded = $ExitCode -eq 0 }
    }

    function Clear-TestVariable {
        Get-ChildItem Env:\DOTCONFIGS_TEST_* | ForEach-Object { Remove-Item -LiteralPath "Env:\$($_.Name)" }
    }
}

Describe 'Install-SqlPlus.ps1' {
    BeforeAll {
        # Two zips sharing one instantclient_<version> folder, like Oracle's.
        function Build-ClientZip([string]$Version, [string]$Package, [string]$File) {
            $dir = Join-Path $TestDrive "zip-$Version-$Package\instantclient_$Version"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content (Join-Path $dir $File) "$Package $Version"
            $zip = Join-Path $TestDrive "instantclient-$Package-$Version.zip"
            # The folder itself is the zip root: instantclient_<version>/<file>.
            if (-not (Test-Path $zip)) { Compress-Archive -Path $dir -DestinationPath $zip }
            $zip
        }
        foreach ($v in '23_9', '23_10') {
            Build-ClientZip -Version $v -Package 'basic' -File 'oci.dll' | Out-Null
            Build-ClientZip -Version $v -Package 'sqlplus' -File 'sqlplus.exe' | Out-Null
        }
    }

    BeforeEach {
        $oracle = Join-Path $TestDrive "oracle-$([guid]::NewGuid().ToString('N'))"
        $parameters = @{ OracleDirectory = $oracle }
        $env:DOTCONFIGS_TEST_IC = '23_9'

        Mock Invoke-WebRequest {
            $package = if ($Uri -like '*sqlplus*') { 'sqlplus' } else { 'basic' }
            $zip = Join-Path $TestDrive "instantclient-$package-$($env:DOTCONFIGS_TEST_IC).zip"
            [pscustomobject]@{ Headers = @{ 'ETag' = "`"$package-$($env:DOTCONFIGS_TEST_IC)`""; 'Content-Length' = "$((Get-Item $zip).Length)" } }
        } -ParameterFilter { $Method -eq 'Head' }
        Mock Invoke-Download {
            $package = if ($Uri -like '*sqlplus*') { 'sqlplus' } else { 'basic' }
            Copy-Item (Join-Path $TestDrive "instantclient-$package-$($env:DOTCONFIGS_TEST_IC).zip") $OutFile
            $OutFile
        }
        Mock Get-InstalledVersion { $null }
        Mock Set-InstalledVersion { }
        Mock Add-PathEntry { $true }
        Mock Remove-PathEntry { $false }
        Mock Invoke-Native { Get-NativeResult @('SQL*Plus: Release 23.0.0.0.0 - Production') }
    }

    AfterEach { Clear-TestVariable }

    It 'installs both zips into one folder, records the fingerprint and sets PATH' {
        $result = Invoke-StepScript 'Install-SqlPlus.ps1' $parameters
        $result.Status | Should -Be 'Success'
        Join-Path $oracle 'instantclient_23_9\sqlplus.exe' | Should -Exist
        Join-Path $oracle 'instantclient_23_9\oci.dll' | Should -Exist
        Should -Invoke Set-InstalledVersion -ParameterFilter { $Version -eq 'instantclient_23_9' -and $Extra.fingerprint -eq '"basic-23_9"|"sqlplus-23_9"' }
        Should -Invoke Add-PathEntry -ParameterFilter { $Path -eq (Join-Path $oracle 'instantclient_23_9') }
    }

    It 'skips without downloading when the fingerprint is unchanged' {
        Invoke-StepScript 'Install-SqlPlus.ps1' $parameters | Out-Null
        Mock Get-InstalledVersion { [pscustomobject]@{ version = 'instantclient_23_9'; fingerprint = '"basic-23_9"|"sqlplus-23_9"' } }
        (Invoke-StepScript 'Install-SqlPlus.ps1' $parameters).Status | Should -Be 'Skipped'
        Should -Invoke Invoke-Download -Times 2 -Exactly
    }

    It 'upgrades to a new release and removes the old folder afterwards' {
        Invoke-StepScript 'Install-SqlPlus.ps1' $parameters | Out-Null
        Mock Get-InstalledVersion { [pscustomobject]@{ version = 'instantclient_23_9'; fingerprint = '"basic-23_9"|"sqlplus-23_9"' } }
        $env:DOTCONFIGS_TEST_IC = '23_10'

        $result = Invoke-StepScript 'Install-SqlPlus.ps1' $parameters
        $result.Data.Previous | Should -Be 'instantclient_23_9'
        Join-Path $oracle 'instantclient_23_10\sqlplus.exe' | Should -Exist
        Join-Path $oracle 'instantclient_23_9' | Should -Not -Exist
        Should -Invoke Remove-PathEntry
    }

    It 'fails without touching the install when a download has the wrong size' {
        Invoke-StepScript 'Install-SqlPlus.ps1' $parameters | Out-Null
        $env:DOTCONFIGS_TEST_IC = '23_10'
        Mock Invoke-Download { Set-Content $OutFile 'truncated'; $OutFile }

        $result = Invoke-StepScript 'Install-SqlPlus.ps1' $parameters
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*advertised*'
        Join-Path $oracle 'instantclient_23_9\sqlplus.exe' | Should -Exist
        Join-Path $oracle 'instantclient_23_10' | Should -Not -Exist
    }

    It 'fails when Oracle cannot be reached' {
        Mock Invoke-WebRequest { throw 'No such host is known.' } -ParameterFilter { $Method -eq 'Head' }
        $result = Invoke-StepScript 'Install-SqlPlus.ps1' $parameters
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*No such host*'
    }
}

Describe 'Install-Psql.ps1' {
    BeforeEach {
        $parameters = @{ Version = 18 }
        $env:DOTCONFIGS_TEST_PSQL = '18.6'      # installed version; empty = not installed
        $env:DOTCONFIGS_TEST_WINGET = '18.6-5'  # what winget show reports

        Mock Get-Command { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }
        Mock Test-Path { [bool]$env:DOTCONFIGS_TEST_PSQL } -ParameterFilter { $LiteralPath -like '*\psql.exe' }
        Mock Invoke-Native { Get-NativeResult @("psql (PostgreSQL) $env:DOTCONFIGS_TEST_PSQL") } -ParameterFilter { $Arguments -contains '--version' }
        Mock Invoke-Native { Get-NativeResult @('Found PostgreSQL 18 [PostgreSQL.PostgreSQL.18]', "Version: $env:DOTCONFIGS_TEST_WINGET") } -ParameterFilter { $Arguments[0] -eq 'show' }
        Mock Invoke-Winget { $env:DOTCONFIGS_TEST_PSQL = ($env:DOTCONFIGS_TEST_WINGET -split '-')[0]; 0 }
        Mock Test-IsAdministrator { $true }
        Mock Add-PathEntry { $true }
    }

    AfterEach { Clear-TestVariable }

    It 'skips when the installed psql matches winget' {
        (Invoke-StepScript 'Install-Psql.ps1' $parameters).Status | Should -Be 'Skipped'
        Should -Invoke Invoke-Winget -Times 0 -Exactly
        Should -Invoke Add-PathEntry -Times 1 -Exactly
    }

    It 'upgrades when winget has a newer build, keeping the client-only override' {
        $env:DOTCONFIGS_TEST_WINGET = '18.7-1'
        $result = Invoke-StepScript 'Install-Psql.ps1' $parameters
        $result.Status | Should -Be 'Success'
        $result.Data.Previous | Should -Be '18.6'
        Should -Invoke Invoke-Winget -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'PostgreSQL.PostgreSQL.18' -and
            $Arguments -contains '--mode unattended --unattendedmodeui none --disable-components server,pgAdmin,stackbuilder'
        }
    }

    It 'installs when psql is missing' {
        $env:DOTCONFIGS_TEST_PSQL = ''
        (Invoke-StepScript 'Install-Psql.ps1' $parameters).Status | Should -Be 'Success'
        Should -Invoke Invoke-Winget -Times 1 -Exactly
    }

    It 'refuses to install without Administrator' {
        $env:DOTCONFIGS_TEST_PSQL = ''
        Mock Test-IsAdministrator { $false }
        (Invoke-StepScript 'Install-Psql.ps1' $parameters).Message | Should -BeLike '*needs Administrator*'
        Should -Invoke Invoke-Winget -Times 0 -Exactly
    }

    It 'reports the exit code and logs when winget fails' {
        $env:DOTCONFIGS_TEST_PSQL = ''
        Mock Invoke-Winget { -2147012894 }
        $result = Invoke-StepScript 'Install-Psql.ps1' $parameters
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*0x80072EE2*winget.log*'
    }

    It 'fails when winget cannot tell whether an update exists' {
        Mock Invoke-Native { Get-NativeResult @() -ExitCode 1 } -ParameterFilter { $Arguments[0] -eq 'show' }
        (Invoke-StepScript 'Install-Psql.ps1' $parameters).Message | Should -BeLike '*cannot check for updates*'
    }
}

Describe 'Setup-PackageManagers.ps1' {
    BeforeAll {
        $depsZip = Join-Path $TestDrive 'deps.zip'
        $depsDir = Join-Path $TestDrive 'deps-src\x64'
        New-Item -ItemType Directory -Path $depsDir -Force | Out-Null
        Set-Content (Join-Path $depsDir 'Microsoft.VCLibs.x64.appx') 'appx'
        Compress-Archive -Path (Join-Path $TestDrive 'deps-src\*') -DestinationPath $depsZip

        $release = [pscustomobject]@{
            tag_name = 'v1.30.100'
            assets   = @(
                [pscustomobject]@{ name = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'; browser_download_url = 'https://example.invalid/b' }
                [pscustomobject]@{ name = 'DesktopAppInstaller_Dependencies.zip'; browser_download_url = 'https://example.invalid/d.zip' }
            )
        }
    }

    BeforeEach {
        $env:DOTCONFIGS_TEST_WINGET = 'v1.29.380'   # installed version; empty = missing
        $env:DOTCONFIGS_TEST_SOURCES = '0'          # exit code of 'winget source list'

        Mock Get-Command { if ($env:DOTCONFIGS_TEST_WINGET) { [pscustomobject]@{ Name = 'winget' } } } -ParameterFilter { $Name -eq 'winget' }
        Mock Invoke-Native { Get-NativeResult @($env:DOTCONFIGS_TEST_WINGET) } -ParameterFilter { $Arguments[0] -eq '--version' }
        Mock Invoke-Native { Get-NativeResult @() -ExitCode ([int]$env:DOTCONFIGS_TEST_SOURCES) } -ParameterFilter { $Arguments[0] -eq 'source' }
        Mock Get-GitHubRelease { $release }
        Mock Get-ReleaseAssetHash { 'a' * 64 }
        Mock Invoke-Download {
            if ($Uri -like '*.zip') { Copy-Item $depsZip $OutFile } else { Set-Content $OutFile 'bundle' }
            $OutFile
        }
        Mock Add-AppxPackage { if ($Path -like '*.msixbundle') { $env:DOTCONFIGS_TEST_WINGET = 'v1.30.100'; $env:DOTCONFIGS_TEST_SOURCES = '0' } }
        Mock Update-SessionPath { }
    }

    AfterEach { Clear-TestVariable }

    It 'skips when winget works and is current' {
        $env:DOTCONFIGS_TEST_WINGET = 'v1.30.100'
        (Invoke-StepScript 'Setup-PackageManagers.ps1').Status | Should -Be 'Skipped'
        Should -Invoke Add-AppxPackage -Times 0 -Exactly
    }

    It 'updates an older winget, dependencies first, verified' {
        $result = Invoke-StepScript 'Setup-PackageManagers.ps1'
        $result.Status | Should -Be 'Success'
        $result.Data.Previous | Should -Be '1.29.380'
        Should -Invoke Add-AppxPackage -Times 1 -Exactly -ParameterFilter { $Path -like '*VCLibs.x64.appx' }
        Should -Invoke Add-AppxPackage -Times 1 -Exactly -ParameterFilter { $Path -like '*.msixbundle' }
        Should -Invoke Invoke-Download -ParameterFilter { $Uri -eq 'https://example.invalid/b' -and $Sha256 -eq ('a' * 64) }
    }

    It 'reports Partial, not Failed, when GitHub cannot be reached but winget works' {
        Mock Get-GitHubRelease { throw 'GitHub API rate limit reached' }
        $result = Invoke-StepScript 'Setup-PackageManagers.ps1'
        $result.Status | Should -Be 'Partial'
        $result.Message | Should -BeLike '*works*rate limit*'
    }

    It 'reports Partial when the update fails but winget works' {
        Mock Add-AppxPackage { throw 'Deployment failed' } -ParameterFilter { $Path -like '*.msixbundle' }
        (Invoke-StepScript 'Setup-PackageManagers.ps1').Status | Should -Be 'Partial'
    }

    It 'installs winget when it is missing' {
        $env:DOTCONFIGS_TEST_WINGET = ''
        (Invoke-StepScript 'Setup-PackageManagers.ps1').Status | Should -Be 'Success'
    }

    It 'fails when winget is missing and GitHub cannot be reached' {
        $env:DOTCONFIGS_TEST_WINGET = ''
        Mock Get-GitHubRelease { throw 'offline' }
        (Invoke-StepScript 'Setup-PackageManagers.ps1').Status | Should -Be 'Failed'
    }

    It 'treats a winget that cannot list its sources as broken, and fails if reinstalling does not fix it' {
        $env:DOTCONFIGS_TEST_SOURCES = '1'
        Mock Add-AppxPackage { }
        $result = Invoke-StepScript 'Setup-PackageManagers.ps1'
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*cannot list its sources*'
    }
}
