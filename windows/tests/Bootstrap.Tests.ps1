#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Tests for windows/Bootstrap.ps1.

.NOTES
The script is dot-sourced with $DotconfigsBootstrapNoRun set, so only its
functions load. Downloads and installers are mocked; git runs for real against
a local repository in $TestDrive. The last block runs in Windows PowerShell 5.1,
which is what the bootstrap really executes in.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeAll/BeforeEach are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeDiscovery {
    $hasWindowsPowerShell = [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue)
    $hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
}

BeforeAll {
    $bootstrapPath = (Resolve-Path (Join-Path $PSScriptRoot '..\Bootstrap.ps1')).Path
    $DotconfigsBootstrapNoRun = $true
    . $bootstrapPath

    $hashA = 'a' * 64
    $release = [pscustomobject]@{
        tag_name = 'v7.9.9'
        assets   = @(
            [pscustomobject]@{ name = 'PowerShell-7.9.9-win-x64.msi'; browser_download_url = 'https://example.invalid/x64.msi' }
            [pscustomobject]@{ name = 'PowerShell-7.9.9-win-arm64.msi'; browser_download_url = 'https://example.invalid/arm64.msi' }
            [pscustomobject]@{ name = 'PowerShell-7.9.9-win-x64.zip'; browser_download_url = 'https://example.invalid/x64.zip' }
            [pscustomobject]@{ name = 'hashes.sha256'; browser_download_url = 'https://example.invalid/hashes.sha256' }
        )
    }

    # A minimal copy of the repository as GitHub's zip lays it out.
    $fixture = Join-Path $TestDrive 'fixture'
    New-Item -ItemType Directory -Path (Join-Path $fixture 'dotconfigs-master\windows') -Force | Out-Null
    Set-Content (Join-Path $fixture 'dotconfigs-master\windows\Install-WindowsEnvironment.ps1') 'exit 0'
    Set-Content (Join-Path $fixture 'dotconfigs-master\README.md') 'readme'
    $repoZip = Join-Path $TestDrive 'repo.zip'
    Compress-Archive -Path (Join-Path $fixture 'dotconfigs-master') -DestinationPath $repoZip
}

Describe 'Get-HashFromList' {
    It 'matches whole names in GNU and BSD lines' {
        $list = @("$('b' * 64) *PowerShell.msi.sig", "$hashA *PowerShell.msi")
        Get-HashFromList -Content $list -FileName 'PowerShell.msi' | Should -Be $hashA
        Get-HashFromList -Content @("SHA256 (PowerShell.msi) = $($hashA.ToUpper())") -FileName 'PowerShell.msi' | Should -Be $hashA
    }

    It 'returns nothing for an unlisted file' {
        Get-HashFromList -Content @('', "$hashA  other.msi") -FileName 'PowerShell.msi' | Should -BeNullOrEmpty
    }
}

Describe 'Select-PwshMsiAsset' {
    It 'picks the <Architecture> MSI and the checksum list' -TestCases @(
        @{ Architecture = 'x64'; Expected = 'PowerShell-7.9.9-win-x64.msi' }
        @{ Architecture = 'arm64'; Expected = 'PowerShell-7.9.9-win-arm64.msi' }
    ) {
        $assets = Select-PwshMsiAsset -Release $release -Architecture $Architecture
        $assets.Msi.name | Should -Be $Expected
        $assets.Hashes.name | Should -Be 'hashes.sha256'
    }

    It 'throws when the architecture has no MSI' {
        { Select-PwshMsiAsset -Release $release -Architecture 'x86' } | Should -Throw '*found 0*'
    }

    It 'refuses a release without hashes.sha256' {
        $unsigned = [pscustomobject]@{ tag_name = 'v7.9.9'; assets = @($release.assets[0]) }
        { Select-PwshMsiAsset -Release $unsigned -Architecture 'x64' } | Should -Throw '*unverified*'
    }
}

Describe 'Get-OSArchitecture' {
    BeforeEach {
        $saved = $env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432
    }
    AfterEach {
        $env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432 = $saved
    }

    It 'maps <Process>/<Wow> to <Expected>' -TestCases @(
        @{ Process = 'AMD64'; Wow = $null; Expected = 'x64' }
        @{ Process = 'ARM64'; Wow = $null; Expected = 'arm64' }
        @{ Process = 'x86'; Wow = 'AMD64'; Expected = 'x64' }
    ) {
        $env:PROCESSOR_ARCHITECTURE = $Process
        $env:PROCESSOR_ARCHITEW6432 = $Wow
        Get-OSArchitecture | Should -Be $Expected
    }
}

Describe 'Install-Pwsh' {
    BeforeEach {
        $work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work | Out-Null
        Mock Sync-BootstrapPath { }
        Mock Get-OSArchitecture { 'x64' }
        Mock Invoke-RestMethod { $release }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget.exe' }

        $msiBytes = 'fake msi'
        $msiHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($msiBytes)))).Hash.ToLower()
        $env:DOTCONFIGS_TEST_HASH = $msiHash
        Mock Invoke-WebRequest {
            if ($Uri -like '*hashes.sha256') {
                Set-Content -LiteralPath $OutFile -Value "$env:DOTCONFIGS_TEST_HASH *PowerShell-7.9.9-win-x64.msi"
            } else {
                Set-Content -LiteralPath $OutFile -Value 'fake msi' -NoNewline
            }
        }
    }

    AfterEach {
        Remove-Item Env:\DOTCONFIGS_TEST_HASH, Env:\DOTCONFIGS_TEST_FLAG -ErrorAction SilentlyContinue
    }

    It 'installs the verified MSI elevated when winget is missing' {
        Mock Find-Pwsh { 'C:\fake\pwsh.exe' }
        Install-Pwsh -WorkDirectory $work | Should -Be 'C:\fake\pwsh.exe'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'msiexec.exe' -and $Verb -eq 'RunAs' -and
            $ArgumentList -like '/i "*PowerShell-7.9.9-win-x64.msi" /passive /norestart ADD_PATH=1'
        }
    }

    It 'refuses an MSI whose checksum does not match' {
        $env:DOTCONFIGS_TEST_HASH = 'c' * 64
        Mock Find-Pwsh { 'C:\fake\pwsh.exe' }
        { Install-Pwsh -WorkDirectory $work } | Should -Throw '*Checksum mismatch*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'fails when the MSI installer fails' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1603 } }
        { Install-Pwsh -WorkDirectory $work } | Should -Throw '*exited with 1603*'
    }

    It 'uses winget when it works, without touching GitHub' {
        Mock Get-Command { [pscustomobject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
        Mock Find-Pwsh { 'C:\winget\pwsh.exe' }
        Install-Pwsh -WorkDirectory $work | Should -Be 'C:\winget\pwsh.exe'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'winget.exe' -and $ArgumentList -like 'install --exact --id Microsoft.PowerShell*'
        }
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'falls back to the MSI when winget leaves pwsh missing' {
        Mock Get-Command { [pscustomobject]@{ Source = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
        # First lookup (after winget) finds nothing, the second (after the MSI) does.
        $env:DOTCONFIGS_TEST_FLAG = Join-Path $work 'flag'
        Mock Find-Pwsh {
            if (Test-Path $env:DOTCONFIGS_TEST_FLAG) { return 'C:\msi\pwsh.exe' }
            New-Item -ItemType File -Path $env:DOTCONFIGS_TEST_FLAG | Out-Null
        }
        Install-Pwsh -WorkDirectory $work | Should -Be 'C:\msi\pwsh.exe'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'msiexec.exe' }
    }
}

Describe 'Get-DotfilesRepository' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        $destination = Join-Path $root '.dotconfigs'
        $work = Join-Path $root 'work'
        New-Item -ItemType Directory -Path $work | Out-Null
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $repoZip -Destination $OutFile }
    }

    It 'downloads and extracts the repository when it is missing' {
        $orchestrator = Get-DotfilesRepository -Destination $destination -ZipUrl 'https://example.invalid/master.zip' -WorkDirectory $work
        $orchestrator | Should -Be (Join-Path $destination 'windows\Install-WindowsEnvironment.ps1')
        $orchestrator | Should -Exist
        Join-Path $destination 'README.md' | Should -Exist
        Get-ChildItem $root -Directory -Filter '.dotconfigs.download-*' | Should -BeNullOrEmpty
    }

    It 'reuses an existing copy without downloading' {
        Copy-Item -Path (Join-Path $fixture 'dotconfigs-master') -Destination $destination -Recurse
        Get-DotfilesRepository -Destination $destination -ZipUrl 'x' -WorkDirectory $work | Should -Exist
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'refuses an unrelated existing folder and leaves it alone' {
        New-Item -ItemType Directory -Path $destination | Out-Null
        Set-Content (Join-Path $destination 'mine.txt') 'keep'
        { Get-DotfilesRepository -Destination $destination -ZipUrl 'x' -WorkDirectory $work } | Should -Throw '*does not contain the dotfiles*'
        Join-Path $destination 'mine.txt' | Should -Exist
    }

    It 'rejects an archive that is not the repository and leaves nothing behind' {
        $other = Join-Path $root 'other.zip'
        $otherSource = Join-Path $root 'other\stuff'
        New-Item -ItemType Directory -Path $otherSource -Force | Out-Null
        Set-Content (Join-Path $otherSource 'x.txt') 'x'
        Compress-Archive -Path $otherSource -DestinationPath $other
        Mock Invoke-WebRequest { Copy-Item -LiteralPath (Join-Path (Split-Path $OutFile | Split-Path) 'other.zip') -Destination $OutFile }

        { Get-DotfilesRepository -Destination $destination -ZipUrl 'x' -WorkDirectory $work } | Should -Throw '*does not look like*'
        $destination | Should -Not -Exist
        Get-ChildItem $root -Directory -Filter '.dotconfigs.download-*' | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-GitClone' -Skip:(-not $hasGit) {
    BeforeAll {
        function Invoke-TestGit { & git -c user.name=test -c user.email=test@example.invalid -c init.defaultBranch=main @args 2>&1 | Out-Null }

        # The "remote": a local repository whose files match the fixture. Its
        # default branch is deliberately 'main' so the clone must pick master.
        $origin = Join-Path $TestDrive 'origin'
        Copy-Item -Path (Join-Path $fixture 'dotconfigs-master') -Destination $origin -Recurse
        Invoke-TestGit -C $origin init --quiet
        Invoke-TestGit -C $origin checkout --quiet -b master
        Invoke-TestGit -C $origin add -A
        Invoke-TestGit -C $origin commit --quiet -m init
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $destination = Join-Path $root '.dotconfigs'
        New-Item -ItemType Directory -Path $root | Out-Null
        Copy-Item -Path (Join-Path $fixture 'dotconfigs-master') -Destination $destination -Recurse
    }

    It 'turns the copy into a clean clone that tracks origin/master' {
        ConvertTo-GitClone -Destination $destination -RepositoryUrl $origin -Branch master
        Join-Path $destination '.git' | Should -Exist
        # Failed once in seven full runs without a captured reason; the git
        # output goes into the failure message so the next occurrence explains itself.
        $status = @(& git -C $destination status --porcelain 2>&1)
        $status | Should -BeNullOrEmpty -Because "git status said: $($status -join ' | ')"
        $upstream = @(& git -C $destination rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>&1)
        $upstream | Should -Be 'origin/master' -Because "git rev-parse said: $($upstream -join ' | ')"
        Get-ChildItem $root -Directory -Filter '.dotconfigs.clone-*' | Should -BeNullOrEmpty
    }

    It 'leaves no .git and no leftovers when the clone fails' {
        { ConvertTo-GitClone -Destination $destination -RepositoryUrl (Join-Path $TestDrive 'missing-origin') -Branch master 2>$null } |
            Should -Throw '*git clone exited*'
        Join-Path $destination '.git' | Should -Not -Exist
        Get-ChildItem $root -Directory -Filter '.dotconfigs.clone-*' | Should -BeNullOrEmpty
    }

    It 'does nothing for an existing clone' {
        New-Item -ItemType Directory -Path (Join-Path $destination '.git') | Out-Null
        ConvertTo-GitClone -Destination $destination -RepositoryUrl 'never-used' -Branch master
        Get-ChildItem (Join-Path $destination '.git') | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-Bootstrap' {
    It "returns the orchestrator's exit code as a single value" {
        $destination = Join-Path $TestDrive 'e2e\.dotconfigs'
        Copy-Item -Path (Join-Path $fixture 'dotconfigs-master') -Destination $destination -Recurse
        Set-Content (Join-Path $destination 'windows\Install-WindowsEnvironment.ps1') 'Write-Output "noise"; exit 3010'
        Mock Find-Pwsh { (Get-Process -Id $PID).Path }
        Mock Sync-BootstrapPath { }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git.exe' }
        $preference = $ErrorActionPreference

        $result = @(Invoke-Bootstrap -Destination $destination 6>$null 3>$null)

        $result | Should -Be @(3010)
        $ErrorActionPreference | Should -Be $preference -Because 'preferences must not leak into the caller'
    }
}

Describe 'Bootstrap.ps1 in Windows PowerShell 5.1' -Skip:(-not $hasWindowsPowerShell) {
    It 'loads through iex without changing the session, and its functions work' {
        # Mirrors 'irm ... | iex': the text runs in the caller's scope.
        $probe = @'
$DotconfigsBootstrapNoRun = $true
iex ([IO.File]::ReadAllText('{0}'))
$hash = 'a' * 64
$release = New-Object PSObject -Property @{{ tag_name = 'v1'; assets = @(
    (New-Object PSObject -Property @{{ name = 'PowerShell-1.0.0-win-x64.msi' }}),
    (New-Object PSObject -Property @{{ name = 'hashes.sha256' }})) }}
'eap=' + $ErrorActionPreference
'hash=' + (Get-HashFromList -Content @("$hash *x.msi") -FileName 'x.msi')
'msi=' + (Select-PwshMsiAsset -Release $release -Architecture 'x64').Msi.name
'arch=' + (Get-OSArchitecture)
'@ -f ($bootstrapPath -replace "'", "''")
        $output = & powershell.exe -NoProfile -NonInteractive -Command $probe
        $LASTEXITCODE | Should -Be 0
        $output | Should -Contain 'eap=Continue'
        $output | Should -Contain ('hash=' + 'a' * 64)
        $output | Should -Contain 'msi=PowerShell-1.0.0-win-x64.msi'
        ($output | Where-Object { $_ -like 'arch=*' }) | Should -Match '^arch=(x64|arm64|x86)$'
    }
}
