#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Unit tests for windows/lib/Common.psm1.

.NOTES
Nothing here touches the real PATH: the PATH tests redirect the registry key to
HKCU\Software\DotconfigsTests and delete it afterwards. File tests run in
Pester's $TestDrive.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeAll/BeforeEach are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeDiscovery {
    # -Skip conditions are evaluated during discovery, before BeforeAll runs.
    Import-Module (Join-Path $PSScriptRoot '..\lib\Common.psm1') -Force
    $canSymlink = Test-CanCreateSymlink
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\Common.psm1') -Force
}

AfterAll {
    Remove-Module Common -ErrorAction SilentlyContinue
}

Describe 'Step result contract' {
    It 'builds a result with status, message and data' {
        $result = New-StepResult Success 'done' -Data @{ Count = 2 }
        $result.Status | Should -Be 'Success'
        $result.Message | Should -Be 'done'
        $result.Data.Count | Should -Be 2
        $result.PSObject.TypeNames | Should -Contain 'Dotconfigs.StepResult'
    }

    It 'rejects ad-hoc status strings' -TestCases @(
        @{ Status = 'error' }, @{ Status = 'installed' }, @{ Status = 'already_installed' }
    ) {
        { New-StepResult $Status } | Should -Throw
    }

    It 'treats <Status> as failed: <Failed>' -TestCases @(
        @{ Status = 'Success';         Failed = $false }
        @{ Status = 'Skipped';         Failed = $false }
        @{ Status = 'RestartRequired'; Failed = $false }
        @{ Status = 'Partial';         Failed = $true }
        @{ Status = 'Failed';          Failed = $true }
    ) {
        Test-StepFailed (New-StepResult $Status) | Should -Be $Failed
    }

    It 'treats a missing result as failed' {
        Test-StepFailed $null | Should -BeTrue
    }

    It 'treats a hashtable result as failed' {
        Test-StepFailed @{ status = 'success' } | Should -BeTrue
    }

    It 'judges the last object when a step leaked extra output' {
        Test-StepFailed @('leaked', (New-StepResult Success)) | Should -BeFalse
        Test-StepFailed @('leaked', (New-StepResult Failed)) | Should -BeTrue
    }
}

Describe 'Invoke-Native' {
    It 'captures output on success' {
        $result = Invoke-Native cmd /c 'echo hello' -Quiet
        $result.Succeeded | Should -BeTrue
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Contain 'hello'
    }

    It 'throws with the exit code and output tail on failure' {
        { Invoke-Native cmd /c 'echo boom & exit 3' -Quiet } | Should -Throw '*exited with 3*boom*'
    }

    It 'returns the result instead of throwing with -NoThrow' {
        $result = Invoke-Native cmd /c 'exit 3' -Quiet -NoThrow
        $result.Succeeded | Should -BeFalse
        $result.ExitCode | Should -Be 3
    }

    It 'accepts extra success codes' {
        (Invoke-Native cmd /c 'exit 3010' -Quiet -AllowedExitCodes 0, 3010).Succeeded | Should -BeTrue
    }

    It 'throws when the program does not exist' {
        { Invoke-Native 'dotconfigs-no-such-program' } | Should -Throw '*not found*'
    }

    It 'passes flags through -Arguments literally, even ones that prefix its own parameters' {
        (Invoke-Native -FilePath cmd -Arguments @('/c', 'echo', '-q', '-n') -Quiet).Output | Should -Contain '-q -n'
    }

    It 'captures stderr without throwing under ErrorActionPreference Stop' {
        $ErrorActionPreference = 'Stop'
        $result = Invoke-Native -FilePath cmd -Arguments @('/c', 'echo oops 1>&2') -Quiet
        $result.Succeeded | Should -BeTrue
        $result.Output | Should -Contain 'oops '
    }
}

Describe 'ConvertTo-CommandLineArgument' {
    It 'quotes <Case>' -TestCases @(
        @{ Case = 'nothing plain';               Value = 'plain';            Expected = 'plain' }
        @{ Case = 'an empty string';             Value = '';                 Expected = '""' }
        @{ Case = 'spaces';                      Value = 'C:\Program Files'; Expected = '"C:\Program Files"' }
        @{ Case = 'embedded quotes';             Value = 'say "hi"';         Expected = '"say \"hi\""' }
        @{ Case = 'a trailing backslash';        Value = 'C:\a b\';          Expected = '"C:\a b\\"' }
        @{ Case = 'backslashes before a quote';  Value = 'a\"b c';           Expected = '"a\\\"b c"' }
        @{ Case = 'backslashes elsewhere as-is'; Value = 'C:\x y\z';         Expected = '"C:\x y\z"' }
    ) {
        ConvertTo-CommandLineArgument $Value | Should -BeExactly $Expected
    }

    It 'round-trips through a real process' {
        $values = @('C:\Program Files\x\', 'say "hi"', '', 'a\\"b', 'plain')
        $line = ($values | ForEach-Object { ConvertTo-CommandLineArgument $_ }) -join ' '
        $pwsh = (Get-Process -Id $PID).Path
        $script = Join-Path $TestDrive 'echo-args.ps1'
        Set-Content $script '$args | ConvertTo-Json -Compress'
        $out = Join-Path $TestDrive 'echo-args.json'
        # Start-Process hands the line to CreateProcess as-is, as Invoke-Winget does.
        Start-Process -FilePath $pwsh -ArgumentList "-NoProfile -File `"$script`" $line" `
            -NoNewWindow -Wait -RedirectStandardOutput $out
        $parsed = @(Get-Content $out -Raw | ConvertFrom-Json)
        $parsed | Should -Be $values
    }
}

Describe 'Invoke-Winget' {
    BeforeEach {
        Mock Start-Sleep -ModuleName Common { }
        Mock Remove-Item -ModuleName Common { }
        Mock Get-ChildItem -ModuleName Common { }
        $env:DOTCONFIGS_TEST_CODES = ''
    }

    AfterEach {
        Remove-Item Env:\DOTCONFIGS_TEST_CODES -ErrorAction SilentlyContinue
    }

    BeforeAll {
        # Exit codes to return, consumed one per winget call (comma-separated).
        function Initialize-FakeWingetExitCode([int[]]$Codes) { $env:DOTCONFIGS_TEST_CODES = $Codes -join ',' }
        $mockWinget = {
            if ($ArgumentList -like 'source reset*') { return [pscustomobject]@{ ExitCode = 0 } }
            $codes = $env:DOTCONFIGS_TEST_CODES -split ','
            $env:DOTCONFIGS_TEST_CODES = ($codes | Select-Object -Skip 1) -join ','
            [pscustomobject]@{ ExitCode = [int]$codes[0] }
        }
    }

    It 'returns 0 without retrying on success' {
        Mock Start-Process -ModuleName Common $mockWinget
        Initialize-FakeWingetExitCode 0
        Invoke-Winget -Arguments 'install', 'x' | Should -Be 0
        Should -Invoke Start-Process -ModuleName Common -Times 1 -Exactly
    }

    It 'retries when Windows Installer is busy (1618)' {
        Mock Start-Process -ModuleName Common $mockWinget
        Initialize-FakeWingetExitCode 1618, 0
        Invoke-Winget -Arguments 'install', 'x' | Should -Be 0
        Should -Invoke Start-Process -ModuleName Common -Times 2 -Exactly
    }

    It 'does not retry other failures by default' {
        Mock Start-Process -ModuleName Common $mockWinget
        Initialize-FakeWingetExitCode 5, 0
        Invoke-Winget -Arguments 'install', 'x' | Should -Be 5
        Should -Invoke Start-Process -ModuleName Common -Times 1 -Exactly
    }

    It 'retries any failure with -RetryOnAnyExitCode and returns the last code' {
        Mock Start-Process -ModuleName Common $mockWinget
        Initialize-FakeWingetExitCode 5, 6, 7
        Invoke-Winget -Arguments 'import' -RetryOnAnyExitCode -MaxAttempts 3 | Should -Be 7
        Should -Invoke Start-Process -ModuleName Common -Times 3 -Exactly
    }

    It 'resets the sources when the index is corrupt' {
        Mock Start-Process -ModuleName Common $mockWinget
        Initialize-FakeWingetExitCode -1978335217, 0
        Invoke-Winget -Arguments 'install', 'x' | Should -Be 0
        Should -Invoke Start-Process -ModuleName Common -Times 1 -Exactly -ParameterFilter { $ArgumentList -like 'source reset*' }
    }

    It 'quotes arguments that contain spaces' {
        Mock Start-Process -ModuleName Common $mockWinget
        Initialize-FakeWingetExitCode 0
        Invoke-Winget -Arguments 'import', '--import-file', 'C:\a b\packages.jsonc' | Out-Null
        Should -Invoke Start-Process -ModuleName Common -ParameterFilter {
            $ArgumentList -eq 'import --import-file "C:\a b\packages.jsonc"'
        }
    }
}

Describe 'Read-Jsonc' {
    It 'handles comments, trailing commas and // inside strings' {
        $path = Join-Path $TestDrive 'sample.jsonc'
        Set-Content -Path $path -Value @'
{
  // line comment
  "url": "https://example.com/path", /* block comment */
  "list": [1, 2, 3,],
}
'@
        $json = Read-Jsonc $path
        $json.url | Should -Be 'https://example.com/path'
        $json.list | Should -Be @(1, 2, 3)
    }

    It 'throws for a missing file' {
        { Read-Jsonc (Join-Path $TestDrive 'missing.jsonc') } | Should -Throw '*not found*'
    }

    It 'throws for invalid JSON' {
        $path = Join-Path $TestDrive 'broken.jsonc'
        Set-Content -Path $path -Value '{ "a": }'
        { Read-Jsonc $path } | Should -Throw
    }
}

Describe 'Get-ChecksumEntry' {
    BeforeAll {
        $a = 'a' * 64
        $b = 'b' * 64
        $c = 'C' * 64
    }

    It 'matches the exact file name, not a longer one' {
        $list = @("$b  tool.zip.sig", "$a  tool.zip", "$c  tool.zip.sbom")
        Get-ChecksumEntry -Content $list -FileName 'tool.zip' | Should -Be $a
    }

    It 'understands GNU binary markers and ./ prefixes' {
        Get-ChecksumEntry -Content @("$a *tool.zip") -FileName 'tool.zip' | Should -Be $a
        Get-ChecksumEntry -Content @("$a  ./tool.zip") -FileName 'tool.zip' | Should -Be $a
    }

    It 'understands the BSD format and lowercases the hash' {
        Get-ChecksumEntry -Content @("SHA256 (tool.zip) = $c") -FileName 'tool.zip' |
            Should -Be $c.ToLowerInvariant()
    }

    It 'returns nothing when the file is not listed' {
        Get-ChecksumEntry -Content @("$a  other.zip", '') -FileName 'tool.zip' | Should -BeNullOrEmpty
    }

    It 'throws on conflicting entries' {
        { Get-ChecksumEntry -Content @("$a  tool.zip", "$b  tool.zip") -FileName 'tool.zip' } |
            Should -Throw '*different hashes*'
    }
}

Describe 'Invoke-Download' {
    BeforeAll {
        # SHA256 of the UTF-8 bytes of 'payload'.
        $payloadHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new(
                    [Text.Encoding]::UTF8.GetBytes('payload'))) -Algorithm SHA256).Hash
    }

    BeforeEach {
        Mock Start-Sleep -ModuleName Common { }
        $out = Join-Path $TestDrive "download-$([guid]::NewGuid()).bin"
    }

    It 'downloads and verifies a matching checksum' {
        Mock Invoke-WebRequest -ModuleName Common { Set-Content -Path $OutFile -Value 'payload' -NoNewline }
        Invoke-Download -Uri 'https://example.invalid/f' -OutFile $out -Sha256 $payloadHash | Should -Be $out
        Test-Path $out | Should -BeTrue
    }

    It 'deletes the file and does not retry on a checksum mismatch' {
        Mock Invoke-WebRequest -ModuleName Common { Set-Content -Path $OutFile -Value 'tampered' -NoNewline }
        { Invoke-Download -Uri 'https://example.invalid/f' -OutFile $out -Sha256 $payloadHash } |
            Should -Throw '*Checksum mismatch*'
        Test-Path $out | Should -BeFalse
        Should -Invoke Invoke-WebRequest -ModuleName Common -Times 1 -Exactly
    }

    It 'retries transient failures and gives up after MaxAttempts' {
        Mock Invoke-WebRequest -ModuleName Common { throw 'connection reset' }
        { Invoke-Download -Uri 'https://example.invalid/f' -OutFile $out -MaxAttempts 3 } |
            Should -Throw '*connection reset*'
        Should -Invoke Invoke-WebRequest -ModuleName Common -Times 3 -Exactly
    }

    It 'succeeds when a retry works' {
        # An environment variable carries state into the mock, which runs in module scope.
        $env:DOTCONFIGS_TEST_FLAG = Join-Path $TestDrive "flag-$([guid]::NewGuid())"
        try {
            Mock Invoke-WebRequest -ModuleName Common {
                if (-not (Test-Path $env:DOTCONFIGS_TEST_FLAG)) {
                    New-Item -ItemType File -Path $env:DOTCONFIGS_TEST_FLAG | Out-Null
                    throw 'transient'
                }
                Set-Content -Path $OutFile -Value 'payload' -NoNewline
            }
            Invoke-Download -Uri 'https://example.invalid/f' -OutFile $out | Should -Be $out
            Should -Invoke Invoke-WebRequest -ModuleName Common -Times 2 -Exactly
        } finally {
            Remove-Item Env:\DOTCONFIGS_TEST_FLAG
        }
    }
}

Describe 'Invoke-Download headers' {
    It 'accepts headers that override its own User-Agent' {
        Mock Invoke-WebRequest -ModuleName Common { Set-Content -Path $OutFile -Value 'x' }
        $out = Join-Path $TestDrive 'headers.bin'
        Invoke-Download -Uri 'https://example.invalid/f' -OutFile $out -Headers (Get-GitHubHeader) | Should -Be $out
        Should -Invoke Invoke-WebRequest -ModuleName Common -ParameterFilter { $Headers['Accept'] -eq 'application/vnd.github+json' }
    }
}

Describe 'Get-ReleaseAssetHash' {
    BeforeAll {
        $hash = 'a' * 64
        function Get-TestRelease([string[]]$Names) {
            [pscustomobject]@{ assets = @($Names | ForEach-Object { [pscustomobject]@{ name = $_; browser_download_url = "https://example.invalid/$_" } }) }
        }
    }

    BeforeEach {
        Mock Invoke-Download -ModuleName Common {
            $content = switch -Wildcard ($Uri) {
                '*.zip.sha256' { "$('A' * 64)  tool.zip" }
                '*SHA-256.txt' { "$('b' * 64)  tool.zip.sig", "$('a' * 64)  tool.zip" }
                '*bad.sha256' { 'not a hash' }
            }
            Set-Content -Path $OutFile -Value $content
            $OutFile
        }
    }

    It "uses GitHub's own asset digest first, without downloading anything" {
        $release = [pscustomobject]@{ assets = @(
                [pscustomobject]@{ name = 'tool.zip'; digest = "sha256:$('C' * 64)"; browser_download_url = 'u' }
                [pscustomobject]@{ name = 'tool.zip.sha256'; browser_download_url = 'https://example.invalid/tool.zip.sha256' }
            ) }
        Get-ReleaseAssetHash -Release $release -AssetName 'tool.zip' -WorkDirectory $TestDrive | Should -Be ('c' * 64)
        Should -Invoke Invoke-Download -ModuleName Common -Times 0 -Exactly
    }

    It 'ignores a digest that is not sha256' {
        $release = [pscustomobject]@{ assets = @(
                [pscustomobject]@{ name = 'tool.zip'; digest = 'md5:abc'; browser_download_url = 'u' }
                [pscustomobject]@{ name = 'SHA-256.txt'; browser_download_url = 'https://example.invalid/SHA-256.txt' }
            ) }
        Get-ReleaseAssetHash -Release $release -AssetName 'tool.zip' -WorkDirectory $TestDrive | Should -Be $hash
    }

    It 'prefers a per-asset .sha256 file' {
        Get-ReleaseAssetHash -Release (Get-TestRelease 'tool.zip', 'tool.zip.sha256', 'SHA-256.txt') -AssetName 'tool.zip' -WorkDirectory $TestDrive |
            Should -Be $hash
        Should -Invoke Invoke-Download -ModuleName Common -Times 1 -Exactly -ParameterFilter { $Uri -like '*tool.zip.sha256' }
    }

    It 'falls back to a checksum list, matching the exact name' {
        Get-ReleaseAssetHash -Release (Get-TestRelease 'tool.zip', 'SHA-256.txt') -AssetName 'tool.zip' -WorkDirectory $TestDrive |
            Should -Be $hash
    }

    It 'returns nothing when the release publishes no checksum' {
        Get-ReleaseAssetHash -Release (Get-TestRelease 'tool.zip') -AssetName 'tool.zip' -WorkDirectory $TestDrive | Should -BeNullOrEmpty
        Should -Invoke Invoke-Download -ModuleName Common -Times 0 -Exactly
    }

    It 'throws on a per-asset file without a hash' {
        { Get-ReleaseAssetHash -Release (Get-TestRelease 'bad', 'bad.sha256') -AssetName 'bad' -WorkDirectory $TestDrive } |
            Should -Throw '*does not contain a SHA256*'
    }
}

Describe 'Installed version records' {
    It 'adds records next to existing ones and reads them back' {
        $path = Join-Path $TestDrive 'versions.json'
        Set-Content $path '{ "supersonic": { "version": "v0.22.1", "asset": "a.zip" } }'

        Set-InstalledVersion -Name 'font:x' -Version 'v3.5.1' -Asset 'f.zip' -Checksum "sha256:$('a' * 64)" -Verified $true -Path $path

        (Get-InstalledVersion -Name 'supersonic' -Path $path).version | Should -Be 'v0.22.1'
        $record = Get-InstalledVersion -Name 'font:x' -Path $path
        $record.version | Should -Be 'v3.5.1'
        $record.verified | Should -BeTrue
        Get-InstalledVersion -Name 'missing' -Path $path | Should -BeNullOrEmpty
        "$path.tmp" | Should -Not -Exist
    }

    It 'returns nothing when there is no file yet' {
        Get-InstalledVersion -Name 'x' -Path (Join-Path $TestDrive 'none.json') | Should -BeNullOrEmpty
    }
}

Describe 'Expand-ArchiveChecked' {
    BeforeAll {
        $payload = Join-Path $TestDrive 'payload'
        New-Item -ItemType Directory -Path $payload | Out-Null
        Set-Content -Path (Join-Path $payload 'a.txt') -Value 'a'
    }

    It 'extracts a zip' {
        $zip = Join-Path $TestDrive 'a.zip'
        Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zip
        $dest = Join-Path $TestDrive 'out-zip'
        Expand-ArchiveChecked $zip $dest
        Join-Path $dest 'a.txt' | Should -Exist
    }

    It 'extracts a tar.gz' {
        $tgz = Join-Path $TestDrive 'a.tar.gz'
        & tar -czf $tgz -C $payload 'a.txt'
        $dest = Join-Path $TestDrive 'out-tgz'
        Expand-ArchiveChecked $tgz $dest
        Join-Path $dest 'a.txt' | Should -Exist
    }

    It 'throws when tar fails on a corrupt archive' {
        $bad = Join-Path $TestDrive 'bad.tar.gz'
        Set-Content -Path $bad -Value 'not an archive'
        { Expand-ArchiveChecked $bad (Join-Path $TestDrive 'out-bad') } | Should -Throw '*tar*exited*'
    }

    It 'throws when the archive is empty' {
        $empty = Join-Path $TestDrive 'empty.zip'
        [IO.Compression.ZipFile]::Open($empty, 'Create').Dispose()
        { Expand-ArchiveChecked $empty (Join-Path $TestDrive 'out-empty') } | Should -Throw '*no files*'
    }

    It 'rejects unsupported formats' {
        { Expand-ArchiveChecked (Join-Path $TestDrive 'a.rar') (Join-Path $TestDrive 'out-rar') } |
            Should -Throw '*Unsupported*'
    }
}

Describe 'PATH helpers' {
    BeforeAll {
        $script:testKey = 'Software\DotconfigsTests\Environment'
    }

    BeforeEach {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:testKey)
        $key.SetValue('Path', '%USERPROFILE%\bin;C:\Tools', 'ExpandString')
        $key.Dispose()

        Mock Get-PathRegistryKey -ModuleName Common {
            # A switch the caller omitted is unset, which strict mode rejects; read the bound parameters instead.
            [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\DotconfigsTests\Environment',
                $PesterBoundParameters['Writable'] -eq $true)
        }
        Mock Send-EnvironmentChange -ModuleName Common { }
        Mock Update-SessionPath -ModuleName Common { }

        function Get-RawTestPath {
            $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:testKey)
            try {
                [pscustomobject]@{
                    Value = $k.GetValue('Path', $null, 'DoNotExpandEnvironmentNames')
                    Kind  = $k.GetValueKind('Path')
                }
            } finally { $k.Dispose() }
        }
    }

    AfterAll {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\DotconfigsTests', $false)
    }

    It 'reads entries without expanding variables' {
        @(Get-PathEntry) | Should -Be @('%USERPROFILE%\bin', 'C:\Tools')
    }

    It 'does not add an entry that differs only by <Case>' -TestCases @(
        @{ Case = 'case';            Entry = 'c:\tools' }
        @{ Case = 'trailing slash';  Entry = 'C:\Tools\' }
        @{ Case = 'variable expansion'; Entry = (Join-Path $env:USERPROFILE 'bin') }
    ) {
        Add-PathEntry -Path $Entry | Should -BeFalse
        (Get-RawTestPath).Value | Should -Be '%USERPROFILE%\bin;C:\Tools'
        Should -Invoke Send-EnvironmentChange -ModuleName Common -Times 0 -Exactly
    }

    It 'appends a new entry and keeps REG_EXPAND_SZ with variables intact' {
        Add-PathEntry -Path 'C:\New' | Should -BeTrue
        $raw = Get-RawTestPath
        $raw.Value | Should -Be '%USERPROFILE%\bin;C:\Tools;C:\New'
        $raw.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
        Should -Invoke Send-EnvironmentChange -ModuleName Common -Times 1 -Exactly
    }

    It 'prepends with -Prepend' {
        Add-PathEntry -Path 'C:\First' -Prepend | Should -BeTrue
        (Get-RawTestPath).Value | Should -Be 'C:\First;%USERPROFILE%\bin;C:\Tools'
    }

    It 'does not write a leading separator into an empty PATH' {
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:testKey, $true)
        $k.SetValue('Path', '', 'ExpandString'); $k.Dispose()

        Add-PathEntry -Path 'C:\Only' | Should -BeTrue
        (Get-RawTestPath).Value | Should -Be 'C:\Only'
    }

    It 'creates PATH as REG_EXPAND_SZ when the value is missing' {
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:testKey, $true)
        $k.DeleteValue('Path'); $k.Dispose()

        Add-PathEntry -Path 'C:\Only' | Should -BeTrue
        (Get-RawTestPath).Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }

    It 'removes an exact entry and keeps the rest unexpanded' {
        Remove-PathEntry -Path 'c:\tools\' | Should -BeTrue
        (Get-RawTestPath).Value | Should -Be '%USERPROFILE%\bin'
    }

    It 'removes entries matching a predicate' {
        Remove-PathEntry -Where { $args[0] -like '%USERPROFILE%*' } | Should -BeTrue
        (Get-RawTestPath).Value | Should -Be 'C:\Tools'
    }

    It 'reports no change when nothing matches' {
        Remove-PathEntry -Path 'C:\Absent' | Should -BeFalse
        Should -Invoke Send-EnvironmentChange -ModuleName Common -Times 0 -Exactly
    }

    It 'writes nothing under -WhatIf' {
        Add-PathEntry -Path 'C:\New' -WhatIf | Should -BeFalse
        Remove-PathEntry -Path 'C:\Tools' -WhatIf | Should -BeFalse
        (Get-RawTestPath).Value | Should -Be '%USERPROFILE%\bin;C:\Tools'
    }
}

Describe 'Link helpers' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $source = Join-Path $root 'source'
        $other = Join-Path $root 'other'
        New-Item -ItemType Directory -Path $source, $other | Out-Null
        Set-Content -Path (Join-Path $source 'keep.txt') -Value 'source data'
        Set-Content -Path (Join-Path $other 'keep.txt') -Value 'other data'
        $target = Join-Path $root 'nested\target'
    }

    It 'creates the link and its parent directory' {
        Set-Link -Source $source -Target $target -Type Junction | Should -Be 'Created'
        Join-Path $target 'keep.txt' | Should -Exist
    }

    It 'leaves a correct link alone' {
        Set-Link -Source $source -Target $target -Type Junction | Out-Null
        Set-Link -Source $source -Target $target -Type Junction | Should -Be 'Unchanged'
    }

    It 'replaces a link that points elsewhere without touching the old target' {
        Set-Link -Source $other -Target $target -Type Junction | Out-Null
        Set-Link -Source $source -Target $target -Type Junction | Should -Be 'Replaced'
        Get-Content (Join-Path $target 'keep.txt') | Should -Be 'source data'
        Get-Content (Join-Path $other 'keep.txt') | Should -Be 'other data'
    }

    It 'moves a real directory aside instead of deleting it' {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Set-Content -Path (Join-Path $target 'mine.txt') -Value 'precious'

        Set-Link -Source $source -Target $target -Type Junction | Should -Be 'BackedUp'

        $backup = Get-ChildItem (Split-Path $target -Parent) -Directory -Filter 'target.bak-*'
        $backup | Should -HaveCount 1
        Get-Content (Join-Path $backup.FullName 'mine.txt') | Should -Be 'precious'
    }

    It 'changes nothing under -WhatIf' {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Set-Content -Path (Join-Path $target 'mine.txt') -Value 'precious'

        Set-Link -Source $source -Target $target -Type Junction -WhatIf | Out-Null

        (Get-Item $target).LinkType | Should -BeNullOrEmpty
        Join-Path $target 'mine.txt' | Should -Exist
    }

    It 'Remove-LinkOnly removes a junction but keeps its target contents' {
        Set-Link -Source $source -Target $target -Type Junction | Out-Null
        Remove-LinkOnly -Path $target
        $target | Should -Not -Exist
        Join-Path $source 'keep.txt' | Should -Exist
    }

    It 'Remove-LinkOnly refuses a real directory' {
        { Remove-LinkOnly -Path $source } | Should -Throw '*not a link*'
        Join-Path $source 'keep.txt' | Should -Exist
    }

    It 'creates file symlinks when the process is allowed to' -Skip:(-not $canSymlink) {
        $file = Join-Path $root 'file-link.txt'
        Set-Link -Source (Join-Path $source 'keep.txt') -Target $file -Type SymbolicLink | Should -Be 'Created'
        (Get-Item $file).LinkType | Should -Be 'SymbolicLink'
    }

    It 'New-BinLink leaves an identical copy alone' {
        $bin = Join-Path $root 'bin'
        New-Item -ItemType Directory -Path $bin | Out-Null
        $copy = Join-Path $bin 'keep.txt'
        Copy-Item (Join-Path $source 'keep.txt') $copy
        $before = [datetime]::new(2000, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
        (Get-Item $copy).LastWriteTimeUtc = $before

        New-BinLink -Source (Join-Path $source 'keep.txt') -BinDirectory $bin | Should -Be 'Unchanged'
        (Get-Item $copy).LastWriteTimeUtc | Should -Be $before
    }

    It 'New-BinLink links or copies, replacing an existing file' {
        $bin = Join-Path $root 'bin'
        New-Item -ItemType Directory -Path $bin | Out-Null
        Set-Content -Path (Join-Path $bin 'keep.txt') -Value 'stale'

        New-BinLink -Source (Join-Path $source 'keep.txt') -BinDirectory $bin | Should -BeIn @('Symlink', 'Copy')
        Get-Content (Join-Path $bin 'keep.txt') | Should -Be 'source data'
    }
}

Describe 'Install-DirectoryAtomic' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $dest = Join-Path $root 'install'

        function Build-Payload([string]$Version) {
            $dir = Join-Path $root "payload-$Version"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -Path (Join-Path $dir 'version.txt') -Value $Version
            $dir
        }
    }

    It 'installs into a new location' {
        Install-DirectoryAtomic -Source (Build-Payload '1') -Destination $dest
        Get-Content (Join-Path $dest 'version.txt') | Should -Be '1'
    }

    It 'replaces an existing install and leaves no backup behind' {
        Install-DirectoryAtomic -Source (Build-Payload '1') -Destination $dest
        Install-DirectoryAtomic -Source (Build-Payload '2') -Destination $dest
        Get-Content (Join-Path $dest 'version.txt') | Should -Be '2'
        Get-ChildItem $root -Directory -Filter 'install.old-*' | Should -BeNullOrEmpty
    }

    It 'keeps the old install when a file in it is locked' {
        Install-DirectoryAtomic -Source (Build-Payload '1') -Destination $dest
        $lock = [IO.File]::Open((Join-Path $dest 'version.txt'), 'Open', 'Read', 'None')
        try {
            { Install-DirectoryAtomic -Source (Build-Payload '2') -Destination $dest } |
                Should -Throw '*still running*'
        } finally {
            $lock.Dispose()
        }
        Get-Content (Join-Path $dest 'version.txt') | Should -Be '1'
    }

    It 'removes leftovers of earlier runs, and only those' {
        Install-DirectoryAtomic -Source (Build-Payload '1') -Destination $dest
        $leftovers = 'install.old-0123abcd', 'install.staging-89abcdef'
        $unrelated = 'install.old-keep', 'install.backup', 'installer.old-0123abcd'
        foreach ($name in $leftovers + $unrelated) { New-Item -ItemType Directory -Path (Join-Path $root $name) | Out-Null }

        Install-DirectoryAtomic -Source (Build-Payload '2') -Destination $dest

        foreach ($name in $leftovers) { Join-Path $root $name | Should -Not -Exist }
        foreach ($name in $unrelated) { Join-Path $root $name | Should -Exist }
    }

    It 'reports a leftover that is still in use and leaves it' {
        $busy = Join-Path $root 'install.old-0123abcd'
        New-Item -ItemType Directory -Path $busy -Force | Out-Null
        Set-Content (Join-Path $busy 'app.exe') 'x'
        $lock = [IO.File]::Open((Join-Path $busy 'app.exe'), 'Open', 'Read', 'Read')
        try {
            Remove-InstallLeftover -Destination $dest | Should -Be $busy
        } finally {
            $lock.Dispose()
        }
        Remove-InstallLeftover -Destination $dest | Should -BeNullOrEmpty
        $busy | Should -Not -Exist
    }

    It 'throws when the source does not exist' {
        { Install-DirectoryAtomic -Source (Join-Path $root 'missing') -Destination $dest } |
            Should -Throw '*not found*'
    }
}

Describe 'Start-DotconfigsLog' {
    It 'writes a transcript and keeps only the newest logs' {
        $logs = Join-Path $TestDrive 'logs'
        New-Item -ItemType Directory -Path $logs | Out-Null
        1..5 | ForEach-Object {
            $old = New-Item -ItemType File -Path (Join-Path $logs "old-$_.log")
            $old.LastWriteTime = (Get-Date).AddDays(-$_)
        }

        $path = Start-DotconfigsLog -LogDirectory $logs -Keep 3
        try {
            $path | Should -Exist
        } finally {
            Stop-Transcript | Out-Null
        }

        $remaining = Get-ChildItem $logs -Filter '*.log'
        $remaining | Should -HaveCount 3
        $remaining.FullName | Should -Contain $path
    }

    It 'adds the suffix to the file name' {
        $path = Start-DotconfigsLog -LogDirectory (Join-Path $TestDrive 'suffixed') -Suffix 'elevated'
        Stop-Transcript | Out-Null
        Split-Path $path -Leaf | Should -Match '^\d{8}-\d{6}-elevated\.log$'
    }
}

Describe 'Environment checks' {
    It 'Test-IsAdministrator and Test-CanCreateSymlink return booleans' {
        Test-IsAdministrator | Should -BeOfType [bool]
        Test-CanCreateSymlink | Should -BeOfType [bool]
    }
}
