#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Tests for the dotfiles, GitHub releases, editor extensions and WSL steps.

.NOTES
Repositories, manifests, link targets and config files live in $TestDrive.
GitHub, downloads, version records, editors, VSIXInstaller, DISM and wsl.exe
are mocked. Real junctions are created (they need no privileges); symbolic
links are only exercised through their failure path unless the process may
create them.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeAll/BeforeEach are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\Common.psm1') -Force
    $windowsDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $repoRoot = Split-Path $windowsDir -Parent

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

Describe 'links.jsonc' {
    It 'lists only existing sources and valid link types' {
        foreach ($link in (Read-Jsonc (Join-Path $windowsDir 'links.jsonc')).links) {
            Join-Path $repoRoot $link.source | Should -Exist -Because "[$($link.app)] links it"
            $link.type | Should -BeIn @('Junction', 'SymbolicLink')
            if ($link.type -eq 'Junction') {
                Test-Path (Join-Path $repoRoot $link.source) -PathType Container | Should -BeTrue -Because 'junctions link folders'
            }
        }
    }
}

Describe 'Configure-Dotfiles.ps1' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $root 'repo'
        New-Item -ItemType Directory -Path (Join-Path $repo 'dirA') -Force | Out-Null
        Set-Content (Join-Path $repo 'dirA\config') 'from repo'
        Set-Content (Join-Path $repo 'file.txt') 'file'
        $env:DOTCONFIGS_TEST_HOME = Join-Path $root 'home'

        $manifest = Join-Path $root 'links.jsonc'
        Set-Content $manifest @'
{ "links": [
  { "app": "a", "source": "dirA", "target": "%DOTCONFIGS_TEST_HOME%\\a", "type": "Junction", "post": ["tool", "refresh"] },
  { "app": "b", "source": "file.txt", "target": "%DOTCONFIGS_TEST_HOME%\\b.txt", "type": "SymbolicLink" }
] }
'@
        $parameters = @{ ManifestPath = $manifest; RepositoryRoot = $repo; LocalBin = (Join-Path $root 'bin') }
        $target = Join-Path $env:DOTCONFIGS_TEST_HOME 'a'

        Mock Add-PathEntry { $true }
        Mock Test-CanCreateSymlink { $false }
        Mock Get-Command { [pscustomobject]@{ Name = 'tool' } } -ParameterFilter { $Name -eq 'tool' }
        Mock Invoke-Native { Get-NativeResult }
    }

    AfterEach { Clear-TestVariable }

    It 'links folders with junctions, expands variables and runs the post command' {
        $result = Invoke-StepScript 'Configure-Dotfiles.ps1' ($parameters + @{ Filter = @('a', 'localbin') })
        $result.Status | Should -Be 'Success'
        (Get-Item $target).LinkType | Should -Be 'Junction'
        Get-Content (Join-Path $target 'config') | Should -Be 'from repo'
        Join-Path $root 'bin' | Should -Exist
        Should -Invoke Invoke-Native -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'tool' -and ($Arguments -join ' ') -eq 'refresh' }
    }

    It 'reports Skipped when every link is already in place' {
        Mock Add-PathEntry { $false }
        Invoke-StepScript 'Configure-Dotfiles.ps1' ($parameters + @{ Filter = @('a', 'localbin') }) | Out-Null
        (Invoke-StepScript 'Configure-Dotfiles.ps1' ($parameters + @{ Filter = @('a', 'localbin') })).Status | Should -Be 'Skipped'
    }

    It 'moves an existing real folder aside instead of deleting it' {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Set-Content (Join-Path $target 'mine') 'precious'
        $result = Invoke-StepScript 'Configure-Dotfiles.ps1' ($parameters + @{ Filter = @('a') })
        $result.Data.BackedUp | Should -Be @($target)
        $backup = Get-ChildItem $env:DOTCONFIGS_TEST_HOME -Directory -Filter 'a.bak-*'
        Get-Content (Join-Path $backup.FullName 'mine') | Should -Be 'precious'
    }

    It 'explains why a file symlink cannot be created, and still links the rest' {
        $result = Invoke-StepScript 'Configure-Dotfiles.ps1' $parameters 3>$null
        $result.Status | Should -Be 'Partial'
        $result.Message | Should -BeLike '*file.txt*Administrator or Developer Mode*'
        (Get-Item $target).LinkType | Should -Be 'Junction'
    }

    It 'reports a failing post command with its exit code' {
        Mock Invoke-Native { Get-NativeResult @('boom') -ExitCode 3 }
        $result = Invoke-StepScript 'Configure-Dotfiles.ps1' ($parameters + @{ Filter = @('a') }) 3>$null
        $result.Status | Should -Be 'Partial'
        $result.Message | Should -BeLike "*'tool refresh' exited with 3*"
    }

    It 'fails a missing source without touching the target' {
        Remove-Item (Join-Path $repo 'dirA') -Recurse -Force # safe: test fixture folder
        $result = Invoke-StepScript 'Configure-Dotfiles.ps1' ($parameters + @{ Filter = @('a') }) 3>$null
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*source not found*'
        $target | Should -Not -Exist
    }

    It 'rejects an unknown -Filter name' {
        (Invoke-StepScript 'Configure-Dotfiles.ps1' ($parameters + @{ Filter = @('nope') })).Message | Should -BeLike '*Unknown app*nope*'
    }
}

Describe 'Install-GitHubReleases.ps1' {
    BeforeAll {
        $toolZip = Join-Path $TestDrive 'tool.zip'
        $toolSrc = Join-Path $TestDrive 'tool-src\tool-1.0'
        New-Item -ItemType Directory -Path $toolSrc -Force | Out-Null
        Set-Content (Join-Path $toolSrc 'tool.exe') 'tool'
        Compress-Archive -Path $toolSrc -DestinationPath $toolZip

        $release = [pscustomobject]@{
            tag_name = 'v1.0'
            assets   = @(
                [pscustomobject]@{ name = 'tool-1.0-windows-x64.zip'; browser_download_url = 'https://example.invalid/tool.zip' }
                [pscustomobject]@{ name = 'tool-1.0-linux-x64.tar.gz'; browser_download_url = 'https://example.invalid/tool.tgz' }
            )
        }
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        $manifest = Join-Path $root 'github-packages.jsonc'
        Set-Content $manifest '{ "packages": [ { "repo": "o/tool", "asset_pattern": "windows-x64\\.zip$", "bin": "tool.exe", "install_dir": "tool" } ] }'
        $parameters = @{ ManifestPath = $manifest; OptDirectory = (Join-Path $root 'opt'); BinDirectory = (Join-Path $root 'bin') }

        Mock Get-GitHubRelease { $release }
        Mock Get-ReleaseAssetHash { 'a' * 64 }
        Mock Invoke-Download { Copy-Item $toolZip $OutFile; $OutFile }
        Mock Get-InstalledVersion { $null }
        Mock Set-InstalledVersion { }
    }

    It 'installs the unwrapped release, links the binary and records a verified install' {
        $result = Invoke-StepScript 'Install-GitHubReleases.ps1' $parameters 3>$null
        $result.Status | Should -Be 'Success'
        Join-Path $root 'opt\tool\tool.exe' | Should -Exist
        Join-Path $root 'bin\tool.exe' | Should -Exist
        Should -Invoke Invoke-Download -ParameterFilter { $Sha256 -eq ('a' * 64) }
        Should -Invoke Set-InstalledVersion -ParameterFilter { $Name -eq 'tool' -and $Version -eq 'v1.0' -and $Verified }
    }

    It 'skips without downloading when the recorded version is current' {
        Invoke-StepScript 'Install-GitHubReleases.ps1' $parameters 3>$null | Out-Null
        Mock Get-InstalledVersion { [pscustomobject]@{ version = 'v1.0' } }
        (Invoke-StepScript 'Install-GitHubReleases.ps1' $parameters 3>$null).Status | Should -Be 'Skipped'
        Should -Invoke Invoke-Download -Times 1 -Exactly
    }

    It 'refuses an ambiguous asset pattern' {
        Set-Content $manifest '{ "packages": [ { "repo": "o/tool", "asset_pattern": "tool", "bin": "tool.exe", "install_dir": "tool" } ] }'
        $result = Invoke-StepScript 'Install-GitHubReleases.ps1' $parameters 3>$null
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*matches 2 assets*'
    }

    It 'honours require_checksum, and records an unverified install otherwise' {
        Mock Get-ReleaseAssetHash { $null }
        Set-Content $manifest '{ "packages": [ { "repo": "o/tool", "asset_pattern": "windows-x64\\.zip$", "bin": "tool.exe", "install_dir": "tool", "require_checksum": true } ] }'
        (Invoke-StepScript 'Install-GitHubReleases.ps1' $parameters 3>$null).Message | Should -BeLike '*require_checksum*'

        Set-Content $manifest '{ "packages": [ { "repo": "o/tool", "asset_pattern": "windows-x64\\.zip$", "bin": "tool.exe", "install_dir": "tool" } ] }'
        (Invoke-StepScript 'Install-GitHubReleases.ps1' $parameters 3>$null).Status | Should -Be 'Success'
        Should -Invoke Set-InstalledVersion -ParameterFilter { -not $Verified -and $Checksum -eq '' }
    }

    It 'fetches a pinned tag instead of the latest release' {
        Set-Content $manifest '{ "packages": [ { "repo": "o/tool", "asset_pattern": "windows-x64\\.zip$", "bin": "tool.exe", "install_dir": "tool", "version": "v0.9" } ] }'
        Invoke-StepScript 'Install-GitHubReleases.ps1' $parameters 3>$null | Out-Null
        Should -Invoke Get-GitHubRelease -ParameterFilter { $Tag -eq 'v0.9' }
    }

    It 'reports Partial when one of several packages fails' {
        Set-Content $manifest @'
{ "packages": [
  { "repo": "o/tool", "asset_pattern": "windows-x64\\.zip$", "bin": "tool.exe", "install_dir": "tool" },
  { "repo": "o/other", "asset_pattern": "nothing-matches", "bin": "x.exe", "install_dir": "other" }
] }
'@
        (Invoke-StepScript 'Install-GitHubReleases.ps1' $parameters 3>$null).Status | Should -Be 'Partial'
    }
}

Describe 'Install-Extensions.ps1' {
    BeforeAll {
        # A minimal VSIX: a zip with an extension.vsixmanifest carrying an identity.
        $vsixSrc = Join-Path $TestDrive 'vsix-src'
        New-Item -ItemType Directory -Path $vsixSrc -Force | Out-Null
        Set-Content (Join-Path $vsixSrc 'extension.vsixmanifest') @'
<PackageManifest><Metadata><Identity Id="Test.Ext" Version="1.2.3" /></Metadata></PackageManifest>
'@
        $vsixZip = Join-Path $TestDrive 'test.zip'
        Compress-Archive -Path (Join-Path $vsixSrc '*') -DestinationPath $vsixZip
        $vsixFile = Join-Path $TestDrive 'test.vsix'
        Copy-Item $vsixZip $vsixFile
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'vscode'), (Join-Path $root 'vs') -Force | Out-Null
        Set-Content (Join-Path $root 'vscode\extensions.json') '{ "extensions": ["a.one", "b.two"], "windows": ["c.three"], "linux": ["d.four"] }'
        Set-Content (Join-Path $root 'vs\extensions.jsonc') '{ "extensions": [ { "id": "Pub.Ext", "name": "Test extension" } ] }'
        $vsPath = Join-Path $root 'VS'
        New-Item -ItemType Directory -Path (Join-Path $vsPath 'Common7\IDE\Extensions') -Force | Out-Null

        Mock Get-Command { [pscustomobject]@{ Name = 'code' } } -ParameterFilter { $Name -eq 'code' }
        Mock Invoke-Native { Get-NativeResult @('a.one') } -ParameterFilter { $FilePath -eq 'code' -and $Arguments[0] -eq '--list-extensions' }
        Mock Invoke-Native { Get-NativeResult } -ParameterFilter { $FilePath -eq 'code' -and $Arguments[0] -eq '--install-extension' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*vswhere.exe' }
        Mock Invoke-Native { Get-NativeResult @((@{ installationPath = $vsPath; instanceId = 'abc123' } | ConvertTo-Json)) } -ParameterFilter { $FilePath -like '*vswhere.exe' }
        Mock Get-Process { $null } -ParameterFilter { $Name -eq 'devenv' }
        Mock Invoke-Download { Copy-Item $vsixFile $OutFile; $OutFile }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
    }

    It 'installs only the missing VS Code extensions for Windows, without --force' {
        $result = Invoke-StepScript 'Install-Extensions.ps1' @{ Editors = @('code'); RepositoryRoot = $root }
        $result.Status | Should -Be 'Success'
        Should -Invoke Invoke-Native -Times 2 -Exactly -ParameterFilter { $Arguments[0] -eq '--install-extension' }
        Should -Invoke Invoke-Native -Times 0 -Exactly -ParameterFilter { $Arguments -contains 'd.four' -or $Arguments -contains '--force' }
    }

    It 'reports Partial when a VS Code extension fails' {
        Mock Invoke-Native { Get-NativeResult @('not found') -ExitCode 1 } -ParameterFilter { $Arguments -contains 'b.two' }
        $result = Invoke-StepScript 'Install-Extensions.ps1' @{ Editors = @('code'); RepositoryRoot = $root } 3>$null
        $result.Status | Should -Be 'Partial'
        $result.Message | Should -BeLike '*b.two (exit 1)*'
    }

    It 'installs a Visual Studio extension scoped to the instance' {
        $result = Invoke-StepScript 'Install-Extensions.ps1' @{ Editors = @('vs'); RepositoryRoot = $root }
        $result.Status | Should -Be 'Success'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*VSIXInstaller.exe' -and $ArgumentList -like '/quiet /instanceIds:abc123 *Pub.Ext.vsix*'
        }
    }

    It 'skips a Visual Studio extension already installed at that version' {
        $installed = Join-Path $vsPath 'Common7\IDE\Extensions\test'
        New-Item -ItemType Directory -Path $installed | Out-Null
        Copy-Item (Join-Path $vsixSrc 'extension.vsixmanifest') $installed
        (Invoke-StepScript 'Install-Extensions.ps1' @{ Editors = @('vs'); RepositoryRoot = $root }).Status | Should -Be 'Skipped'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'refuses a download that is not a VSIX' {
        Mock Invoke-Download { Set-Content $OutFile '<html>error</html>'; $OutFile }
        $result = Invoke-StepScript 'Install-Extensions.ps1' @{ Editors = @('vs'); RepositoryRoot = $root } 3>$null
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*no readable extension.vsixmanifest*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'fails, rather than skips, while Visual Studio is running' {
        Mock Get-Process { [pscustomobject]@{ Name = 'devenv' } } -ParameterFilter { $Name -eq 'devenv' }
        (Invoke-StepScript 'Install-Extensions.ps1' @{ Editors = @('vs'); RepositoryRoot = $root }).Message | Should -BeLike '*close it*'
    }

    It 'skips an editor that is not installed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'code' }
        $result = Invoke-StepScript 'Install-Extensions.ps1' @{ Editors = @('code'); RepositoryRoot = $root }
        $result.Status | Should -Be 'Skipped'
        $result.Message | Should -BeLike '*not on PATH*'
    }
}

Describe 'Install-WSL.ps1' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        $parameters = @{ WslConfigPath = (Join-Path $root '.wslconfig'); WslgConfigPath = (Join-Path $root '.wslgconfig') }
        $env:DOTCONFIGS_TEST_DISTROS = 'FedoraLinux-42'

        Mock Test-IsAdministrator { $true }
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{ State = 'Enabled' } }
        Mock Enable-WindowsOptionalFeature { [pscustomobject]@{ RestartNeeded = $true } }
        Mock Invoke-Native { Get-NativeResult ($env:DOTCONFIGS_TEST_DISTROS -split ',') } -ParameterFilter { $Arguments[0] -eq '--list' }
        Mock Invoke-Native { $env:DOTCONFIGS_TEST_DISTROS += ',Ubuntu-24.04'; Get-NativeResult } -ParameterFilter { $Arguments[0] -eq '--install' }
        Mock Invoke-Native { Get-NativeResult } -ParameterFilter { $Arguments[0] -in '--update', '--set-default' }
    }

    AfterEach { Clear-TestVariable }

    It 'asks for a restart after enabling features, without rebooting' {
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{ State = 'Disabled' } }
        Mock Restart-Computer { throw 'must not reboot' }
        $result = Invoke-StepScript 'Install-WSL.ps1' ($parameters + @{ FeaturesOnly = $true })
        $result.Status | Should -Be 'RestartRequired'
        Should -Invoke Enable-WindowsOptionalFeature -Times 2 -Exactly
    }

    It 'merges its keys into an existing .wslconfig, keeping other settings and a backup' {
        Set-Content $parameters.WslConfigPath "[wsl2]`nmemory=8GB"
        Invoke-StepScript 'Install-WSL.ps1' ($parameters + @{ FeaturesOnly = $true }) | Out-Null
        $config = Get-Content $parameters.WslConfigPath
        $config | Should -Contain 'memory=8GB'
        $config | Should -Contain 'guiApplications=true'
        Get-Content "$($parameters.WslConfigPath).dotconfigs-backup" | Should -Contain 'memory=8GB'
        (Invoke-StepScript 'Install-WSL.ps1' ($parameters + @{ FeaturesOnly = $true })).Status | Should -Be 'Skipped'
    }

    It 'installs the distribution without launching it and makes it the default' {
        $result = Invoke-StepScript 'Install-WSL.ps1' $parameters
        $result.Status | Should -Be 'Success'
        Should -Invoke Invoke-Native -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq '--install --distribution Ubuntu-24.04 --no-launch' }
        Should -Invoke Invoke-Native -ParameterFilter { ($Arguments -join ' ') -eq '--set-default Ubuntu-24.04' }
    }

    It 'skips when the distribution is installed and the configs are current' {
        $env:DOTCONFIGS_TEST_DISTROS = 'Ubuntu-24.04'
        Invoke-StepScript 'Install-WSL.ps1' $parameters | Out-Null
        (Invoke-StepScript 'Install-WSL.ps1' $parameters).Status | Should -Be 'Skipped'
        Should -Invoke Invoke-Native -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq '--install' }
    }

    It 'reports Partial when wsl --update fails' {
        $env:DOTCONFIGS_TEST_DISTROS = 'Ubuntu-24.04'
        Mock Invoke-Native { Get-NativeResult @('no network') -ExitCode 1 } -ParameterFilter { $Arguments[0] -eq '--update' }
        (Invoke-StepScript 'Install-WSL.ps1' $parameters 3>$null).Status | Should -Be 'Partial'
    }

    It 'fails when the installed distribution does not appear' {
        Mock Invoke-Native { Get-NativeResult } -ParameterFilter { $Arguments[0] -eq '--install' }
        (Invoke-StepScript 'Install-WSL.ps1' $parameters).Message | Should -BeLike '*is not listed*'
    }

    It 'fails without Administrator' {
        Mock Test-IsAdministrator { $false }
        (Invoke-StepScript 'Install-WSL.ps1' $parameters).Message | Should -BeLike '*needs Administrator*'
    }
}
