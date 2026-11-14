#Requires -Version 7
<#
.SYNOPSIS
    Zellij workspace commands: zj (projects), zja (agent), zjr (dev/test/build).
.DESCRIPTION
    Imported by the profile. The layout these feed is zellij/layouts/service.kdl
    and the plugin they talk to is zellij/plugins/pilot; zellij/README.md has
    the whole workflow.

    Projects live under $env:ZJ_PROJECTS (default ~/Projects) as
    <client>/<service> (or <client>/<group>/<service>). Each client is one
    Zellij session and each service one tab in it, so `zj acme/cerberus`
    lands in session "acme", tab "cerberus". A project directly under the
    root is its own session with one tab.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Re-imported by the thread job in Open-ZjTarget.
$script:ModuleFile = $PSCommandPath

# Files whose presence makes a folder a project: the picker lists it and
# stops descending, and zjr knows what to run in it.
$script:ProjectMarkers = @(
    '.git', '*.sln', '*.slnx', '*.csproj', 'package.json', 'pyproject.toml',
    'requirements.txt', 'Cargo.toml', 'go.mod', 'pom.xml', 'build.gradle', 'build.gradle.kts'
)

# --- Pure helpers (tested in windows/tests/Zellij.Tests.ps1) ------------------

<#
.SYNOPSIS
    The folder that holds the client folders: $env:ZJ_PROJECTS or ~/Projects.
#>
function Get-ZjProjectRoot {
    [OutputType([string])]
    param()

    if ($env:ZJ_PROJECTS) { $env:ZJ_PROJECTS } else { Join-Path $HOME 'Projects' }
}

<#
.SYNOPSIS
    A Zellij session name from a folder name: anything but letters, digits,
    '-', '_' and '.' becomes '_' (session names end up in pipe and file paths),
    and leading or trailing dots go.
.DESCRIPTION
    On Windows (Zellij 0.46.0) a session named '.dotconfigs' starts and runs,
    but `zellij ls`, the session manager, `-s` and resurrection never find it:
    once you switch away it is unreachable, and CLI calls from its own panes
    fail. A trailing dot breaks the same way (Windows drops it from file
    names). So ~/.dotconfigs becomes session 'dotconfigs'.
#>
function ConvertTo-ZjSessionName {
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)

    $clean = ($Name -replace '[^\w.-]', '_').Trim('.')
    if ($clean) { $clean } else { '_' }
}

<#
.SYNOPSIS
    Where a folder opens: the session (its client), the tab (its own name)
    and the folder itself.
.PARAMETER Directory
    The project folder.
.PARAMETER Root
    The projects root; a folder outside it becomes its own session.
#>
function Get-ZjTarget {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string]$Root = (Get-ZjProjectRoot)
    )

    $full = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $leaf = Split-Path -Leaf $full

    $client = $leaf
    if ($full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        $client = $full.Substring($rootFull.Length + 1).Split([char[]]'\/')[0]
    }

    [pscustomobject]@{
        Session = ConvertTo-ZjSessionName $client
        Tab = $leaf
        Directory = $full
    }
}

<#
.SYNOPSIS
    Quote a string for a KDL document.
#>
function ConvertTo-KdlString {
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

<#
.SYNOPSIS
    The service layout for one tab, with its name and folder filled in.
.DESCRIPTION
    layouts/service.kdl names its tab "service" and has no cwd, so it also
    works as a plain layout file. Zellij's --cwd is ignored for sessions
    started in the background, and a layout passed to an existing session
    cannot be renamed afterwards, so the name and folder go into the KDL.
.PARAMETER Template
    The text of layouts/service.kdl.
#>
function New-ZjServiceLayout {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Returns a string; nothing is changed.')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Directory
    )

    $anchor = 'ui name="service" focus=true'
    if (-not $Template.Contains($anchor)) {
        throw "The service layout no longer contains '$anchor'; update New-ZjServiceLayout to match it."
    }
    $Template.Replace($anchor, "ui name=$(ConvertTo-KdlString $Name) cwd=$(ConvertTo-KdlString $Directory) focus=true")
}

<#
.SYNOPSIS
    Parse `zellij list-sessions --no-formatting` into Name, Exited, Current.
#>
function ConvertFrom-ZjSessionList {
    [OutputType([pscustomobject])]
    param([AllowEmptyCollection()][string[]]$Line = @())

    foreach ($entry in $Line) {
        if ($entry -match '^(?<name>\S+) \[Created ') {
            [pscustomobject]@{
                Name = $Matches.name
                Exited = $entry.Contains('(EXITED')
                Current = $entry.Contains('(current)')
            }
        }
    }
}

<#
.SYNOPSIS
    Parse `zellij action list-tabs` into Id, Position, Name.
#>
function ConvertFrom-ZjTabList {
    [OutputType([pscustomobject])]
    param([AllowEmptyCollection()][string[]]$Line = @())

    foreach ($entry in $Line) {
        if ($entry -match '^(?<id>\d+)\s+(?<position>\d+)\s+(?<name>.+?)\s*$') {
            [pscustomobject]@{
                Id = [int]$Matches.id
                Position = [int]$Matches.position
                Name = $Matches.name
            }
        }
    }
}

<#
.SYNOPSIS
    Claude Code's folder name for a project: every character that is not a
    letter or digit becomes '-' (C:\Users\me\.app -> C--Users-me--app).
#>
function ConvertTo-ClaudeProjectKey {
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    [IO.Path]::GetFullPath($Path).TrimEnd('\', '/') -replace '[^A-Za-z0-9]', '-'
}

<#
.SYNOPSIS
    Whether Claude Code has a conversation to continue for a folder.
#>
function Test-ClaudeConversation {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ConfigDirectory = $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' })
    )

    $dir = Join-Path $ConfigDirectory "projects\$(ConvertTo-ClaudeProjectKey $Path)"
    [bool](Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -File -ErrorAction Ignore | Select-Object -First 1)
}

<#
.SYNOPSIS
    Whether an agent has a conversation to continue in a folder. Only
    OpenCode and Claude Code are known; any other agent answers false.
.DESCRIPTION
    OpenCode: `opencode session list` lists the folder's project sessions
    (~120 ms through its background service); nothing listed, or an error,
    means start fresh. Claude Code: a transcript in ~/.claude/projects.
#>
function Test-AgentConversation {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Agent,
        [Parameter(Mandatory)][string]$Path
    )

    switch ($Agent) {
        'opencode' {
            Push-Location -LiteralPath $Path
            try {
                $sessions = & opencode session list --max-count 1 2>$null
                return ($LASTEXITCODE -eq 0 -and [bool]($sessions | Where-Object { $_ -match '^ses_' }))
            } catch {
                return $false
            } finally {
                Pop-Location
            }
        }
        'claude' { return Test-ClaudeConversation -Path $Path }
        default { return $false }
    }
}

<#
.SYNOPSIS
    The OSC 7501 sequence that tells Zellij's inbox what a program is doing.
.PARAMETER State
    idle, working, done, blocked, error, or clear (removes the status).
.LINK
    https://zellij.dev/documentation/inbox-integrations.html
#>
function Format-ProgramStatus {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateSet('idle', 'working', 'done', 'blocked', 'error', 'clear')][string]$State,
        [string]$Message,
        [string]$App
    )

    $fields = @("state=$State")
    if ($Message) { $fields += 'msg=' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Message)) }
    if ($App) { $fields += "app=$App" }
    "`e]7501;$($fields -join ':')`e\"
}

<#
.SYNOPSIS
    What zjr runs for a task in a project folder.
.DESCRIPTION
    A .zjr.json in the folder wins ({"dev": "...", "test": "...", "build": "..."},
    each a pwsh command line). Otherwise the project kind decides:

      dotnet  Aspire AppHost: aspire run (or dotnet run --project); else
              dotnet watch on the web project (or the only project);
              dotnet test / dotnet build at the root
      node    the lockfile picks pnpm, bun, yarn or npm; dev runs the "dev"
              script (or "start"), test and build their scripts
      python  uv run (python without uv): manage.py runserver, main.py or
              app.py; pytest
      rust    cargo run / test / build
      go      go run . / go test ./... / go build ./...
      maven   (mvnw or mvn) spring-boot:run / test / package
      gradle  (gradlew or gradle) bootRun / test / build

    A folder with none of those (a monorepo) still gets a dev command: its
    Aspire AppHost up to three levels down, else docker compose up.

    Returns nothing when there is no command for the task.
.OUTPUTS
    Kind, Task and Command (the program and its arguments).
#>
function Get-ProjectTask {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('dev', 'test', 'build')][string]$Task
    )

    $has = { param($pattern) [bool](Get-ChildItem -LiteralPath $Path -Filter $pattern -Force -ErrorAction Ignore | Select-Object -First 1) }
    $onPath = { param($name) [bool](Get-Command $name -CommandType Application -ErrorAction Ignore) }
    $result = { param($kind, [string[]]$command) [pscustomobject]@{ Kind = $kind; Task = $Task; Command = $command } }

    $override = Join-Path $Path '.zjr.json'
    if (Test-Path -LiteralPath $override) {
        $tasks = Get-Content -LiteralPath $override -Raw | ConvertFrom-Json -AsHashtable
        if ($tasks.ContainsKey($Task)) {
            return & $result 'custom' @('pwsh', '-NoLogo', '-NoProfile', '-Command', $tasks[$Task])
        }
    }

    if ((& $has '*.sln') -or (& $has '*.slnx') -or (& $has '*.csproj')) {
        if ($Task -ne 'dev') { return & $result 'dotnet' @('dotnet', $Task) }

        $projects = @(Get-ChildItem -LiteralPath $Path -Filter '*.csproj' -Recurse -Depth 3 -File -ErrorAction Ignore |
                Where-Object FullName -NotMatch '[\\/](bin|obj|node_modules)[\\/]')
        $text = @{}
        foreach ($p in $projects) { $text[$p.FullName] = Get-Content -LiteralPath $p.FullName -Raw }
        $relative = { param($file) [IO.Path]::GetRelativePath($Path, $file) }

        $appHost = $projects | Where-Object { $text[$_.FullName] -match 'Aspire\.AppHost\.Sdk|<IsAspireHost>\s*true' } | Select-Object -First 1
        if ($appHost) {
            if (& $onPath 'aspire') { return & $result 'dotnet' @('aspire', 'run') }
            return & $result 'dotnet' @('dotnet', 'run', '--project', (& $relative $appHost.FullName))
        }
        $web = @($projects | Where-Object { $text[$_.FullName] -match 'Sdk="Microsoft\.NET\.Sdk\.Web"' })
        $target = if ($web.Count -ge 1) { $web[0] } elseif ($projects.Count -eq 1) { $projects[0] }
        if ($target) { return & $result 'dotnet' @('dotnet', 'watch', '--project', (& $relative $target.FullName)) }
        return
    }

    if (& $has 'package.json') {
        $manager = if (& $has 'pnpm-lock.yaml') { 'pnpm' }
        elseif ((& $has 'bun.lock') -or (& $has 'bun.lockb')) { 'bun' }
        elseif (& $has 'yarn.lock') { 'yarn' }
        else { 'npm' }

        $package = Get-Content -LiteralPath (Join-Path $Path 'package.json') -Raw | ConvertFrom-Json -AsHashtable
        $scripts = if ($package.ContainsKey('scripts') -and $package.scripts) { $package.scripts } else { @{} }
        $script = switch ($Task) {
            'dev' { @('dev', 'start') | Where-Object { $scripts.ContainsKey($_) } | Select-Object -First 1 }
            default { if ($scripts.ContainsKey($Task)) { $Task } }
        }
        if ($script) { return & $result 'node' @($manager, 'run', $script) }
        return
    }

    if ((& $has 'pyproject.toml') -or (& $has 'requirements.txt')) {
        # @(): assigning an if unrolls a one-element array into a string.
        $run = @(if ((& $has 'uv.lock') -or (& $onPath 'uv')) { 'uv', 'run' } else { 'python' })
        switch ($Task) {
            'test' { return & $result 'python' ($run + @('pytest')) }
            'build' { if (& $onPath 'uv') { return & $result 'python' @('uv', 'build') }; return }
            'dev' {
                if (& $has 'manage.py') { return & $result 'python' ($run + @('manage.py', 'runserver')) }
                foreach ($entry in 'main.py', 'app.py') {
                    if (& $has $entry) { return & $result 'python' ($run + @($entry)) }
                }
                return
            }
        }
    }

    if (& $has 'Cargo.toml') {
        return & $result 'rust' @('cargo', $(if ($Task -eq 'dev') { 'run' } else { $Task }))
    }

    if (& $has 'go.mod') {
        $command = switch ($Task) { 'dev' { @('go', 'run', '.') } 'test' { @('go', 'test', './...') } 'build' { @('go', 'build', './...') } }
        return & $result 'go' $command
    }

    if (& $has 'pom.xml') {
        $mvn = if (& $has 'mvnw.cmd') { (Join-Path $Path 'mvnw.cmd') } else { 'mvn' }
        $goal = switch ($Task) { 'dev' { 'spring-boot:run' } 'test' { 'test' } 'build' { 'package' } }
        return & $result 'maven' @($mvn, $goal)
    }

    if ((& $has 'build.gradle') -or (& $has 'build.gradle.kts')) {
        $gradle = if (& $has 'gradlew.bat') { (Join-Path $Path 'gradlew.bat') } else { 'gradle' }
        $goal = switch ($Task) { 'dev' { 'bootRun' } 'test' { 'test' } 'build' { 'build' } }
        return & $result 'gradle' @($gradle, $goal)
    }

    # Monorepos with nothing at the root: the whole stack through its Aspire
    # AppHost (aspire run finds it), or through docker compose.
    # AppHosts come as a project (Aspire.AppHost.Sdk) or, since Aspire 13, as
    # a single apphost.cs file.
    if ($Task -ne 'dev') { return }
    $appHost = Get-ChildItem -LiteralPath $Path -Include '*.csproj', 'apphost.cs' -Recurse -Depth 3 -File -ErrorAction Ignore |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj|node_modules)[\\/]' -and
            ($_.Name -eq 'apphost.cs' -or (Get-Content -LiteralPath $_.FullName -Raw) -match 'Aspire\.AppHost\.Sdk|<IsAspireHost>\s*true') } |
        Select-Object -First 1
    if ($appHost) {
        if (& $onPath 'aspire') { return & $result 'aspire' @('aspire', 'run') }
        $relative = [IO.Path]::GetRelativePath($Path, $appHost.FullName)
        if ($appHost.Extension -eq '.cs') { return & $result 'aspire' @('dotnet', 'run', $relative) }
        return & $result 'aspire' @('dotnet', 'run', '--project', $relative)
    }
    foreach ($compose in 'compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml') {
        if (& $has $compose) { return & $result 'compose' @('docker', 'compose', 'up') }
    }
}

<#
.SYNOPSIS
    Whether a folder is a project (any of the marker files).
#>
function Test-ZjProject {
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    foreach ($marker in $script:ProjectMarkers) {
        if (Get-ChildItem -LiteralPath $Path -Filter $marker -Force -ErrorAction Ignore | Select-Object -First 1) {
            return $true
        }
    }
    $false
}

<#
.SYNOPSIS
    The folders the picker offers, relative to the root: every folder down to
    -Depth, without descending into projects (their src/ and docs/ are not
    services) or hidden and dependency folders.
#>
function Get-ZjProjectList {
    [OutputType([string])]
    param(
        [string]$Root = (Get-ZjProjectRoot),
        [int]$Depth = 3
    )

    $skip = '^(\.|node_modules$|bin$|obj$|dist$|target$|__MACOSX$)'
    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue(@{ Path = $Root; Level = 0 })
    while ($queue.Count) {
        $item = $queue.Dequeue()
        foreach ($dir in Get-ChildItem -LiteralPath $item.Path -Directory -ErrorAction Ignore | Sort-Object Name) {
            if ($dir.Name -match $skip) { continue }
            [IO.Path]::GetRelativePath($Root, $dir.FullName)
            if ($item.Level + 1 -lt $Depth -and -not (Test-ZjProject $dir.FullName)) {
                $queue.Enqueue(@{ Path = $dir.FullName; Level = $item.Level + 1 })
            }
        }
    }
}

<#
.SYNOPSIS
    The project list for the session hub (zellij/plugins/pilot): the root,
    then the projects, most used first.
.DESCRIPTION
    The hub runs this in the background (projects_command in config.kdl) and
    caches the result, so it never waits for PowerShell.
.OUTPUTS
    "root=<folder>", then one project per line relative to the root with /
    separators, ranked by zoxide and then by name.
#>
function Get-ZjHubProject {
    [OutputType([string])]
    param([string]$Root = (Get-ZjProjectRoot))

    "root=$Root"
    $rank = @{}
    $i = 0
    if (Get-Command zoxide -CommandType Application -ErrorAction Ignore) {
        foreach ($path in zoxide query --list 2>$null) { $rank[$path.TrimEnd('\')] ??= $i++ }
    }
    Get-ZjProjectList -Root $Root |
        Sort-Object { $r = $rank[(Join-Path $Root $_)]; if ($null -eq $r) { [int]::MaxValue } else { $r } }, { $_ } |
        ForEach-Object { $_.Replace('\', '/') }
}

# --- Zellij calls ---------------------------------------------------------------

<#
.SYNOPSIS
    Run zellij and return its output lines; throw on failure unless -NoThrow.
#>
function Invoke-Zellij {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$NoThrow
    )

    $output = & zellij @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $NoThrow) {
        throw "zellij $($Arguments[0..([Math]::Min(2, $Arguments.Count - 1))] -join ' ') failed ($LASTEXITCODE): $($output -join ' ')"
    }
    $output | ForEach-Object { "$_" }
}

<#
.SYNOPSIS
    The service layout template (layouts/service.kdl in Zellij's config folder).
#>
function Get-ZjServiceTemplate {
    $configDir = if ($env:ZELLIJ_CONFIG_DIR) { $env:ZELLIJ_CONFIG_DIR } else { Join-Path $env:APPDATA 'Zellij\config' }
    Get-Content -LiteralPath (Join-Path $configDir 'layouts\service.kdl') -Raw
}

<#
.SYNOPSIS
    Wait until a session has a client attached, so a tab added to it gets a
    real size (a session nobody looks at is too small for the layout).
#>
function Wait-ZjClient {
    param(
        [Parameter(Mandatory)][string]$Session,
        [double]$TimeoutSeconds = 15
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $clients = Invoke-Zellij -Arguments @('--session', $Session, 'action', 'list-clients') -NoThrow
        if (@($clients | Where-Object { $_ -match '^\d+\s' }).Count) { return $true }
        Start-Sleep -Milliseconds 150
    }
    $false
}

<#
.SYNOPSIS
    In a session with a client, focus the target's tab, adding it first if
    it is missing.
#>
function Open-ZjTab {
    param([Parameter(Mandatory)][pscustomobject]$Target)

    $tabs = ConvertFrom-ZjTabList (Invoke-Zellij -Arguments @('--session', $Target.Session, 'action', 'list-tabs') -NoThrow)
    if ($tabs | Where-Object Name -EQ $Target.Tab) {
        Invoke-Zellij -Arguments @('--session', $Target.Session, 'action', 'go-to-tab-name', $Target.Tab) | Out-Null
    } else {
        # With --session, --layout-string adds the tab to that session and
        # focuses it for the clients in it.
        $layout = New-ZjServiceLayout -Template (Get-ZjServiceTemplate) -Name $Target.Tab -Directory $Target.Directory
        Invoke-Zellij -Arguments @('--session', $Target.Session, '--layout-string', $layout) | Out-Null
    }
}

<#
.SYNOPSIS
    Open a target: its session, then its tab, from inside Zellij or outside.
#>
function Open-ZjTarget {
    param([Parameter(Mandatory)][pscustomobject]$Target)

    $sessions = @(ConvertFrom-ZjSessionList (Invoke-Zellij -Arguments @('list-sessions', '--no-formatting') -NoThrow))
    $existing = $sessions | Where-Object Name -EQ $Target.Session

    if ($env:ZELLIJ) {
        if ($env:ZELLIJ_SESSION_NAME -eq $Target.Session) {
            Open-ZjTab $Target
            return
        }
        # `zellij action switch-session` would move the CLI's own connection,
        # not this client; the pilot plugin moves the client focused on this
        # pane (zellij/plugins/pilot, "switch").
        $payload = if ($existing) { '-' } else {
            New-ZjServiceLayout -Template (Get-ZjServiceTemplate) -Name $Target.Tab -Directory $Target.Directory
        }
        Invoke-Zellij -Arguments @('pipe', '--name', 'switch',
            '--args', "session=$($Target.Session),pane=$env:ZELLIJ_PANE_ID", '--', $payload) | Out-Null
        if ($existing -and (Wait-ZjClient $Target.Session)) {
            Open-ZjTab $Target
        }
        return
    }

    if (-not $existing) {
        # -n reads a file, and only at start-up, so the file can go when the
        # client returns (detach or quit).
        $file = Join-Path ([IO.Path]::GetTempPath()) "zj-$($Target.Session)-$([guid]::NewGuid().ToString('n')).kdl"
        New-ZjServiceLayout -Template (Get-ZjServiceTemplate) -Name $Target.Tab -Directory $Target.Directory |
            Set-Content -LiteralPath $file -Encoding utf8NoBOM
        try {
            zellij --session $Target.Session --new-session-with-layout $file
        } finally {
            Remove-Item -LiteralPath $file -ErrorAction Ignore
        }
        return
    }

    # An existing (or resurrectable) session: the tab is added or focused
    # once this client is in, from a background thread, because attaching
    # holds the console until detach.
    $job = Start-ThreadJob -ScriptBlock {
        $target = $using:Target
        if (Wait-ZjClient $target.Session -TimeoutSeconds 30) { Open-ZjTab $target }
    } -InitializationScript ([scriptblock]::Create("Import-Module '$($script:ModuleFile.Replace("'", "''"))'"))
    try {
        zellij attach $Target.Session
    } finally {
        Remove-Job -Job $job -Force -ErrorAction Ignore
    }
}

# --- Commands ---------------------------------------------------------------------

<#
.SYNOPSIS
    Start the session hub's lobby: Zellij showing the hub full screen, until
    it is quit there with q.
.DESCRIPTION
    Each round starts a throwaway session named lobby-<id> with the lobby
    layout (zellij/layouts/lobby.kdl). Picking something in the hub moves
    this client to that session; when the client later detaches or the
    session ends, the hub comes back. Quitting the hub with q leaves a
    marker file, which ends the loop.

    Lobbies are deleted by the pilot plugin once nobody is in them.
#>
function Enter-ZjLobby {
    while ($true) {
        $name = "lobby-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
        # The hub writes this in Zellij's temp folder when it is quit with q.
        $marker = Join-Path ([IO.Path]::GetTempPath()) "zellij\hub-quit-$name"
        $started = [DateTime]::UtcNow

        zellij --session $name --new-session-with-layout lobby

        if (Test-Path -LiteralPath $marker) {
            Remove-Item -LiteralPath $marker -ErrorAction Ignore
            return
        }
        # Zellij failing to start (a config error, say) must not spin.
        if ($LASTEXITCODE -ne 0 -or ([DateTime]::UtcNow - $started).TotalSeconds -lt 2) {
            Write-Warning "Zellij ended right away (exit code $LASTEXITCODE); not starting the hub again."
            return
        }
    }
}

<#
.SYNOPSIS
    Open the session hub, or with a folder open that project: its client's
    session, its own tab (Neovim, agent, dev, test and shell panes).
.DESCRIPTION
    Without arguments it opens the hub (zellij/README.md, "The hub"): one
    list of running sessions, saved sessions and projects. Outside Zellij
    that is the lobby, full screen (Enter-ZjLobby); inside, the same popup
    as Alt s.

    With a folder it goes straight there, without the hub: inside Zellij it
    switches this client, outside it attaches.
.PARAMETER Project
    A folder: absolute, relative, or relative to the projects root.
.EXAMPLE
    zj
.EXAMPLE
    zj acme/cerberus
.EXAMPLE
    zj .
#>
function zj {
    param([Parameter(Position = 0)][string]$Project)

    if (-not $Project) {
        if ($env:ZELLIJ) {
            Invoke-Zellij -Arguments @('pipe', '--name', 'hub', '--', 'open') | Out-Null
        } else {
            Enter-ZjLobby
        }
        return
    }

    $root = Get-ZjProjectRoot
    foreach ($candidate in $Project, (Join-Path $root $Project)) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $dir = (Resolve-Path -LiteralPath $candidate).ProviderPath
            Open-ZjTarget (Get-ZjTarget -Directory $dir -Root $root)
            return
        }
    }
    Write-Error "zj: no folder '$Project' here or under $root. Run zj without arguments to pick from the hub."
}

<#
.SYNOPSIS
    Start the coding agent for the current folder: $env:ZJ_AGENT (default
    opencode), continuing the folder's last conversation if it has one.
.DESCRIPTION
    The service layout's agent pane runs this, so after a reboot the
    resurrected pane picks the conversation up where it stopped. OpenCode
    and Claude Code continue with --continue; other agents start fresh.
    Arguments given to zja go to the agent instead.
.EXAMPLE
    zja
.EXAMPLE
    $env:ZJ_AGENT = 'claude'; zja
#>
function zja {
    $agent = if ($env:ZJ_AGENT) { $env:ZJ_AGENT } else { 'opencode' }
    $arguments = @($args)
    if ($arguments.Count -eq 0 -and (Test-AgentConversation -Agent $agent -Path $PWD.ProviderPath)) {
        $arguments = @('--continue')
    }
    & $agent @arguments
}

<#
.SYNOPSIS
    Run the project's dev server, tests or build (see Get-ProjectTask), and
    report it to Zellij's inbox.
.DESCRIPTION
    The service layout's dev and test panes run this, suspended until Enter,
    as `zjr dev; exit $LASTEXITCODE`: $LASTEXITCODE is the command's, so the
    pane exits with it and Zellij marks the pane as done or failed.
.PARAMETER Task
    dev (default), test or build.
.PARAMETER WhatIf
    Print the command without running it.
.EXAMPLE
    zjr test
#>
function zjr {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Position = 0)][ValidateSet('dev', 'test', 'build')][string]$Task = 'dev')

    $plan = Get-ProjectTask -Path $PWD.ProviderPath -Task $Task
    if (-not $plan) {
        Write-Host "zjr: no $Task command for $($PWD.ProviderPath)." -ForegroundColor Yellow
        Write-Host 'Add one in .zjr.json: { "dev": "...", "test": "...", "build": "..." }'
        $global:LASTEXITCODE = 2
        return
    }

    $line = $plan.Command -join ' '
    Write-Host "zjr $Task ($($plan.Kind)): $line" -ForegroundColor Cyan
    if (-not $PSCmdlet.ShouldProcess($PWD.ProviderPath, $line)) { return }

    [Console]::Write((Format-ProgramStatus -State working -Message "$Task`: $line" -App 'zjr'))
    $program, $rest = $plan.Command
    & $program @rest
    $code = $LASTEXITCODE
    $state = if ($code -eq 0) { 'done' } else { 'error' }
    [Console]::Write((Format-ProgramStatus -State $state -Message "$Task exited with $code" -App 'zjr'))
    $global:LASTEXITCODE = $code
}

# Tab completion for the zellij CLI. Zellij generates a 400 KB script that
# takes ~55 ms to load, so a stub stands in until the first Tab after
# `zellij`: it generates the script (once per zellij.exe build, which has no
# file version, hence the timestamp), loads it, which replaces the stub, and
# answers that first Tab through it.
Register-ArgumentCompleter -Native -CommandName zellij -ScriptBlock {
    # Completers get their arguments by position; the word is unused here.
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $wordToComplete

    $exe = Get-Command zellij -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if (-not $exe) { return }
    $stamp = (Get-Item -LiteralPath $exe.Source).LastWriteTimeUtc.ToString('yyyyMMddHHmmss')
    $script = Join-Path $HOME ".cache\zellij\completion-$stamp.ps1"
    if (-not (Test-Path -LiteralPath $script)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script) | Out-Null
        & $exe.Source setup --generate-completion powershell 2>$null | Set-Content -LiteralPath $script -Encoding utf8NoBOM
    }
    . $script

    $column = $cursorPosition - $commandAst.Extent.StartOffset
    (TabExpansion2 -inputScript $commandAst.Extent.Text -cursorColumn $column).CompletionMatches
}

Export-ModuleMember -Function zj, zja, zjr, Enter-ZjLobby, Get-ZjTarget, Get-ZjProjectList, Get-ZjHubProject, Get-ProjectTask, Wait-ZjClient, Open-ZjTab
