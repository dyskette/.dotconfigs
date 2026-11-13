#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.6' }
<#
.SYNOPSIS
Tests for powershell/Zellij.psm1 (zj, zja, zjr) and the layout it fills in.

.NOTES
Only the pure helpers are tested; zellij itself is never called, so no
session is touched. Project folders are built in TestDrive.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables set in BeforeAll/BeforeEach are read in It blocks; the analyzer cannot see Pester scoping.')]
param()

BeforeAll {
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $repo 'powershell\Zellij.psm1') -Force -DisableNameChecking
    $template = Get-Content -LiteralPath (Join-Path $repo 'zellij\layouts\service.kdl') -Raw

    # A project folder in TestDrive with the given files (relative path ->
    # content).
    function Build-TestProject {
        param([string]$Name, [hashtable]$Files = @{})
        $dir = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        foreach ($file in $Files.Keys) {
            $path = Join-Path $dir $file
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
            Set-Content -LiteralPath $path -Value $Files[$file]
        }
        $dir
    }
}

AfterAll {
    Remove-Module Zellij -ErrorAction SilentlyContinue
}

Describe 'Get-ZjTarget' {
    It 'maps <Relative> to session <Session>, tab <Tab>' -TestCases @(
        @{ Relative = 'acme\cerberus'; Session = 'acme'; Tab = 'cerberus' }
        @{ Relative = 'acme\cerberus\ORDERS_API'; Session = 'acme'; Tab = 'ORDERS_API' }
        @{ Relative = 'sentinel'; Session = 'sentinel'; Tab = 'sentinel' }
        @{ Relative = 'my client\app.v2'; Session = 'my_client'; Tab = 'app.v2' }
    ) {
        $target = Get-ZjTarget -Directory "C:\Projects\$Relative" -Root 'C:\Projects'
        $target.Session | Should -Be $Session
        $target.Tab | Should -Be $Tab
        $target.Directory | Should -Be "C:\Projects\$Relative"
    }

    It 'matches the root without regard to case or a trailing separator' {
        (Get-ZjTarget -Directory 'c:\projects\acme\api\' -Root 'C:\Projects\').Session | Should -Be 'acme'
    }

    It 'makes a folder outside the root its own session' {
        $target = Get-ZjTarget -Directory 'D:\work\tool' -Root 'C:\Projects'
        $target.Session | Should -Be 'tool'
        $target.Tab | Should -Be 'tool'
    }

    It 'does not treat a sibling with the same prefix as inside the root' {
        (Get-ZjTarget -Directory 'C:\ProjectsOld\acme\api' -Root 'C:\Projects').Session | Should -Be 'api'
    }
}

Describe 'New-ZjServiceLayout' {
    It 'names the tab and sets its folder, KDL-escaped' {
        $layout = InModuleScope Zellij -Parameters @{ Template = $template } {
            New-ZjServiceLayout -Template $Template -Name 'api "v2"' -Directory 'C:\Projects\acme\api'
        }
        $layout | Should -Match ([regex]::Escape('ui name="api \"v2\"" cwd="C:\\Projects\\acme\\api" focus=true'))
        $layout | Should -Not -Match 'ui name="service"'
    }

    It 'fails loudly when the template no longer has the anchor' {
        { InModuleScope Zellij { New-ZjServiceLayout -Template 'layout { }' -Name a -Directory b } } |
            Should -Throw '*no longer contains*'
    }

    It 'keeps the pane names pilot and the README rely on' {
        foreach ($name in 'editor', 'agent', 'dev', 'test', 'shell') {
            $template | Should -Match "pane name=`"$name`""
        }
    }
}

Describe 'Session and tab lists' {
    It 'parses list-sessions --no-formatting' {
        $sessions = InModuleScope Zellij {
            ConvertFrom-ZjSessionList @(
                'acme [Created 2h 3m ago] (current)'
                'globex [Created 1day ago] (EXITED - attach to resurrect)'
                'initech [Created 5s ago] '
            )
        }
        $sessions.Name | Should -Be 'acme', 'globex', 'initech'
        $sessions.Exited | Should -Be $false, $true, $false
        $sessions.Current | Should -Be $true, $false, $false
    }

    It 'parses list-tabs, names with spaces included' {
        $tabs = InModuleScope Zellij {
            ConvertFrom-ZjTabList @('TAB_ID  POSITION  NAME', '0  0  cerberus', '4  1  my tab ')
        }
        $tabs.Name | Should -Be 'cerberus', 'my tab'
        $tabs.Position | Should -Be 0, 1
        $tabs.Id | Should -Be 0, 4
    }
}

Describe 'Claude Code conversations' {
    It 'encodes <Path> as <Key>' -TestCases @(
        @{ Path = 'C:\Users\me\.dotconfigs'; Key = 'C--Users-me--dotconfigs' }
        @{ Path = 'C:\Users\me\Projects\a\MO_API-X\'; Key = 'C--Users-me-Projects-a-MO-API-X' }
    ) {
        InModuleScope Zellij -Parameters @{ P = $Path } { ConvertTo-ClaudeProjectKey $P } | Should -Be $Key
    }

    It 'finds a conversation only when the folder has a transcript' {
        $config = Join-Path $TestDrive 'claude'
        $project = 'C:\Users\me\app'
        InModuleScope Zellij -Parameters @{ C = $config; P = $project } { Test-ClaudeConversation -Path $P -ConfigDirectory $C } |
            Should -BeFalse

        $dir = Join-Path $config 'projects\C--Users-me-app'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'abc.jsonl') -Value '{}'
        InModuleScope Zellij -Parameters @{ C = $config; P = $project } { Test-ClaudeConversation -Path $P -ConfigDirectory $C } |
            Should -BeTrue
    }
}

Describe 'Test-AgentConversation' {
    It 'continues OpenCode when the project lists a session' {
        Mock -ModuleName Zellij opencode { $global:LASTEXITCODE = 0; "ses_abc`tTitle`t11/13/2026" }
        InModuleScope Zellij -Parameters @{ P = $TestDrive } { Test-AgentConversation -Agent opencode -Path $P } | Should -BeTrue
        Should -Invoke -ModuleName Zellij opencode -ParameterFilter { $args -contains 'list' }
    }

    It 'starts OpenCode fresh when the project has no session' {
        Mock -ModuleName Zellij opencode { $global:LASTEXITCODE = 0 }
        InModuleScope Zellij -Parameters @{ P = $TestDrive } { Test-AgentConversation -Agent opencode -Path $P } | Should -BeFalse
    }

    It 'starts OpenCode fresh when listing fails' {
        Mock -ModuleName Zellij opencode { $global:LASTEXITCODE = 1; 'ses_stale' }
        InModuleScope Zellij -Parameters @{ P = $TestDrive } { Test-AgentConversation -Agent opencode -Path $P } | Should -BeFalse
    }

    It 'leaves the current folder as it was' {
        Mock -ModuleName Zellij opencode { $global:LASTEXITCODE = 0 }
        $before = (Get-Location).Path
        InModuleScope Zellij -Parameters @{ P = $TestDrive } { Test-AgentConversation -Agent opencode -Path $P } | Out-Null
        (Get-Location).Path | Should -Be $before
    }

    It 'never continues an unknown agent' {
        InModuleScope Zellij -Parameters @{ P = $TestDrive } { Test-AgentConversation -Agent codex -Path $P } | Should -BeFalse
    }
}

Describe 'Format-ProgramStatus' {
    It 'writes OSC 7501 with a base64 message' {
        $sequence = InModuleScope Zellij { Format-ProgramStatus -State working -Message 'dev: npm run dev' -App zjr }
        $message = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('dev: npm run dev'))
        $sequence | Should -Be "`e]7501;state=working:msg=$($message):app=zjr`e\"
    }

    It 'rejects states the protocol does not have' {
        { InModuleScope Zellij { Format-ProgramStatus -State running } } | Should -Throw
    }
}

Describe 'Get-ProjectTask' {
    BeforeAll {
        # No uv or aspire on PATH, so the fallbacks are what is tested;
        # Get-Command still answers for everything else.
        Mock -ModuleName Zellij Get-Command { $null } -ParameterFilter { $Name -in 'uv', 'aspire' }
    }

    It 'runs a .zjr.json command first' {
        $dir = Build-TestProject 'custom' @{ '.zjr.json' = '{ "dev": "make serve" }'; 'package.json' = '{}' }
        (Get-ProjectTask -Path $dir -Task dev).Command | Should -Be 'pwsh', '-NoLogo', '-NoProfile', '-Command', 'make serve'
    }

    It 'falls back to detection for tasks .zjr.json leaves out' {
        $dir = Build-TestProject 'custom-partial' @{ '.zjr.json' = '{ "dev": "make serve" }'; 'Cargo.toml' = '' }
        (Get-ProjectTask -Path $dir -Task test).Command | Should -Be 'cargo', 'test'
    }

    It 'watches the web project of a solution' {
        $dir = Build-TestProject 'dotnet-web' @{
            'App.sln' = ''
            'src\Lib\Lib.csproj' = '<Project Sdk="Microsoft.NET.Sdk"></Project>'
            'src\Api\Api.csproj' = '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>'
        }
        (Get-ProjectTask -Path $dir -Task dev).Command | Should -Be 'dotnet', 'watch', '--project', 'src\Api\Api.csproj'
        (Get-ProjectTask -Path $dir -Task test).Command | Should -Be 'dotnet', 'test'
    }

    It 'runs an Aspire AppHost project with dotnet run when the aspire CLI is missing' {
        $dir = Build-TestProject 'dotnet-aspire' @{
            'App.slnx' = ''
            'AppHost\AppHost.csproj' = '<Project Sdk="Aspire.AppHost.Sdk/13.0.0"></Project>'
            'Api\Api.csproj' = '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>'
        }
        (Get-ProjectTask -Path $dir -Task dev).Command | Should -Be 'dotnet', 'run', '--project', 'AppHost\AppHost.csproj'
    }

    It 'skips build output when looking for projects' {
        $dir = Build-TestProject 'dotnet-bin' @{
            'Only.csproj' = '<Project Sdk="Microsoft.NET.Sdk"></Project>'
            'bin\Debug\Copy.csproj' = '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>'
        }
        (Get-ProjectTask -Path $dir -Task dev).Command | Should -Be 'dotnet', 'watch', '--project', 'Only.csproj'
    }

    It 'picks <Manager> from <Lockfile> and the <Script> script' -TestCases @(
        @{ Lockfile = 'pnpm-lock.yaml'; Manager = 'pnpm'; Scripts = '{"dev":"vite"}'; Script = 'dev' }
        @{ Lockfile = 'bun.lock'; Manager = 'bun'; Scripts = '{"dev":"vite"}'; Script = 'dev' }
        @{ Lockfile = 'yarn.lock'; Manager = 'yarn'; Scripts = '{"start":"ng serve"}'; Script = 'start' }
        @{ Lockfile = 'package-lock.json'; Manager = 'npm'; Scripts = '{"dev":"next","start":"next start"}'; Script = 'dev' }
    ) {
        $dir = Build-TestProject "node-$Manager-$Script" @{ 'package.json' = "{`"scripts`": $Scripts}"; $Lockfile = '' }
        (Get-ProjectTask -Path $dir -Task dev).Command | Should -Be $Manager, 'run', $Script
    }

    It 'has no node command for a task without a script' {
        $dir = Build-TestProject 'node-no-test' @{ 'package.json' = '{"scripts": {"dev": "vite"}}' }
        Get-ProjectTask -Path $dir -Task test | Should -BeNullOrEmpty
        $bare = Build-TestProject 'node-no-scripts' @{ 'package.json' = '{"name": "x"}' }
        Get-ProjectTask -Path $bare -Task dev | Should -BeNullOrEmpty
    }

    It 'runs python entry points through uv when the project has uv.lock' {
        $dir = Build-TestProject 'python-uv' @{ 'pyproject.toml' = ''; 'uv.lock' = ''; 'main.py' = '' }
        (Get-ProjectTask -Path $dir -Task dev).Command | Should -Be 'uv', 'run', 'main.py'
        (Get-ProjectTask -Path $dir -Task test).Command | Should -Be 'uv', 'run', 'pytest'
    }

    It 'prefers manage.py and falls back to python without uv' {
        $dir = Build-TestProject 'python-django' @{ 'requirements.txt' = ''; 'manage.py' = ''; 'main.py' = '' }
        (Get-ProjectTask -Path $dir -Task dev).Command | Should -Be 'python', 'manage.py', 'runserver'
    }

    It 'maps <Marker> to <Dev>' -TestCases @(
        @{ Marker = 'Cargo.toml'; Dev = 'cargo run' }
        @{ Marker = 'go.mod'; Dev = 'go run .' }
        @{ Marker = 'pom.xml'; Dev = 'mvn spring-boot:run' }
        @{ Marker = 'build.gradle.kts'; Dev = 'gradle bootRun' }
    ) {
        $dir = Build-TestProject "marker-$Marker" @{ $Marker = '' }
        (Get-ProjectTask -Path $dir -Task dev).Command -join ' ' | Should -Be $Dev
    }

    It 'uses the project''s Maven wrapper' {
        $dir = Build-TestProject 'maven-wrapper' @{ 'pom.xml' = ''; 'mvnw.cmd' = '' }
        (Get-ProjectTask -Path $dir -Task test).Command | Should -Be (Join-Path $dir 'mvnw.cmd'), 'test'
    }

    It 'runs a monorepo through its single-file AppHost' {
        $dir = Build-TestProject 'mono-aspire' @{ 'aspire\apphost.cs' = ''; 'docker-compose.yml' = ''; 'frontend\x.txt' = '' }
        (Get-ProjectTask -Path $dir -Task dev).Command | Should -Be 'dotnet', 'run', 'aspire\apphost.cs'
        Get-ProjectTask -Path $dir -Task test | Should -BeNullOrEmpty
    }

    It 'runs a monorepo through docker compose without an AppHost' {
        $dir = Build-TestProject 'mono-compose' @{ 'compose.yaml' = '' }
        (Get-ProjectTask -Path $dir -Task dev).Command | Should -Be 'docker', 'compose', 'up'
    }

    It 'has nothing for a folder it does not recognise' {
        $dir = Build-TestProject 'empty' @{ 'README.md' = '' }
        Get-ProjectTask -Path $dir -Task dev | Should -BeNullOrEmpty
    }
}

Describe 'Get-ZjProjectList' {
    BeforeAll {
        $root = Join-Path $TestDrive 'Projects'
        foreach ($file in @(
                'acme\api\.git\HEAD'
                'acme\api\src\Program.cs'
                'acme\web\package.json'
                'acme\web\node_modules\x\package.json'
                'acme\group\svc\go.mod'
                'solo\Cargo.toml'
                'solo\src\main.rs'
                '.hidden\x.txt'
            )) {
            $path = Join-Path $root $file
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
            Set-Content -LiteralPath $path -Value ''
        }
        $list = @(Get-ZjProjectList -Root $root)
    }

    It 'lists clients, services and grouped services' {
        foreach ($expected in 'acme', 'acme\api', 'acme\web', 'acme\group', 'acme\group\svc', 'solo') {
            $list | Should -Contain $expected
        }
    }

    It 'does not descend into projects or list hidden folders' {
        $list | Should -Not -Contain 'acme\api\src'
        $list | Should -Not -Contain 'solo\src'
        $list | Should -Not -Contain '.hidden'
        ($list | Where-Object { $_ -match 'node_modules' }) | Should -BeNullOrEmpty
    }

    It 'stops at the requested depth' {
        Get-ZjProjectList -Root $root -Depth 2 | Should -Not -Contain 'acme\group\svc'
    }
}
