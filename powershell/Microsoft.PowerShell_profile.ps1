#Requires -Version 7
# Interactive profile: no Set-StrictMode or ErrorActionPreference here, both
# would apply to every command typed in the shell.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '',
    Justification = 'Prompt and fnm state must outlive the profile script and be visible to prompt and event handlers.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
    Justification = "fnm's documented PowerShell integration is 'fnm env | Invoke-Expression'.")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'wordToComplete',
    Justification = 'Argument completers receive their arguments positionally; the dotnet one does not need the word.')]
param()

# UTF-8 both ways with native programs. The console defaults to the OEM code
# page (437), so a path fzf, fd or rg prints with ñ or á would come back
# garbled when captured into a variable.
[Console]::InputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

Set-PSReadLineKeyHandler -Key 'Ctrl+p' -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key 'Ctrl+n' -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key "Ctrl+y" -Function AcceptSuggestion
Set-PSReadLineKeyHandler -Key "Ctrl+d" -Function DeleteCharOrExit

# One PATH scan for every tool the profile wires up, instead of one per tool.
$tools = @{}
Get-Command nvim, yazi, fnm, dotnet -CommandType Application -ErrorAction SilentlyContinue |
    ForEach-Object { $tools[$_.Name -replace '\.exe$', ''] = $_.Source }

# The prompt: [󰣀 ][domain\]user@host dir ❯
#
# Who and where never change within a shell, so that part is built once; each
# prompt only shortens the path and picks the status colour, with no external
# program or module, so it stays instant. Colours are the terminal's own 16,
# so they follow its light/dark theme by themselves.
& {
    $user = [Environment]::UserName
    $isAdmin = if ($IsWindows) {
        [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    } else {
        $user -eq 'root'
    }
    $global:PromptChar = if ($isAdmin) {
        '#'
    } else {
        '❯'
    }
    $head = if ($isAdmin) {
        "`e[1;31m$user`e[0m"
    } else {
        "`e[32m$user`e[0m"
    }

    # Domain accounts (AD, Entra ID) are domain\user, as whoami prints
    # them, and that is the name runas, ACLs and shares want. A local
    # account's domain is the machine itself, so it is left out there.
    $domain = if ($IsWindows) {
        [Environment]::UserDomainName
    }
    if ($domain -and $domain -ne [Environment]::MachineName) {
        $head = "`e[2m$($domain.ToLower())\`e[22m$head"
    }

    if ($env:SSH_CONNECTION) {
        $head = "`e[33m󰣀`e[0m $head"
    }

    $global:PromptHead = "$head`e[34m@$([Environment]::MachineName.ToLower())`e[0m "
}

# PSReadLine redraws this part of the prompt in red while the line has a
# syntax error.
Set-PSReadLineOption -PromptText "$global:PromptChar "

function prompt {
    $ok = $?
    $loc = $executionContext.SessionState.Path.CurrentLocation

    # Follow the Windows app theme for psmux, which has no theme detection of
    # its own: set-theme.ps1 reads SYSTEM_COLOR_THEME. BAT_THEME is the same
    # answer for bat, which cannot detect it inside an fzf preview (see
    # CliTools.ps1). A direct registry read, as Get-ItemProperty costs a
    # provider round trip on every prompt.
    if ($IsWindows) {
        $light = [Microsoft.Win32.Registry]::GetValue(
            'HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme', 0)
        $env:SYSTEM_COLOR_THEME = if ($light) {
            'light'
        } else {
            'dark'
        }
        $env:BAT_THEME = "everforest-$($env:SYSTEM_COLOR_THEME)-medium"
    }

    # Shell integration (OSC 133): the end of the last command with its exit
    # code (D), then where the prompt starts (A) and where it ends (B); the
    # command start (C) is sent from the history handler below. Zellij uses
    # them for the inbox (a long command finished or failed), for jumping
    # between prompts (Alt g s, then [ and ]) and for copying the last
    # command's output (Alt g s c); Windows Terminal draws scrollbar marks.
    # D only after a C, so the first prompt reports no phantom command.
    $osc = ""
    if ($global:CommandRunning) {
        $code = if ($ok) { 0 } elseif ($global:LASTEXITCODE) { $global:LASTEXITCODE } else { 1 }
        $osc += "`e]133;D;$code`a"
        $global:CommandRunning = $false
    }
    $osc += "`e]133;A`a"

    # Report the working directory so a new pane, split or tab opens where
    # this one is. PowerShell's cd does not change the process's directory,
    # so the terminal cannot find it on its own.
    #
    # Inside Zellij: OSC 7, which it reads (and forwards to the terminal
    # outside). Not OSC 9;9, ConEmu's, which Windows Terminal honours:
    # Zellij reads OSC 9 as a desktop notification.
    if ($loc.Provider.Name -eq "FileSystem") {
        if ($env:ZELLIJ) {
            $uri = [Uri]::new($loc.ProviderPath).AbsoluteUri -replace '^file:///', "file://$([Environment]::MachineName)/"
            $osc += "`e]7;$uri`e\"
        } else {
            $osc += "`e]9;9;`"$($loc.ProviderPath)`"`e\"
        }
    }

    # Title at the prompt: the current folder (~ for home), as bash does,
    # so a tab or psmux window reads as where the shell is. Without it the
    # title is pwsh.exe's full path.
    $folder = if ($loc.ProviderPath -eq $HOME) {
        "~"
    } else {
        Split-Path -Leaf $loc.ProviderPath
    }
    $host.UI.Write("$osc`e]2;$folder`a")

    # ~ for home, and only the last three folders, as bash's
    # PROMPT_DIRTRIM=3: ~\...\a\b\c
    $path = if ($loc.Provider.Name -eq "FileSystem") {
        $loc.ProviderPath
    } else {
        $loc.Path
    }
    $sep = [IO.Path]::DirectorySeparatorChar
    if ($path.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase) -and
        ($path.Length -eq $HOME.Length -or $path[$HOME.Length] -eq $sep)) {
        $path = "~" + $path.Substring($HOME.Length)
    }
    $parts = $path.Split($sep)
    if ($parts.Count -gt 4) {
        $path = $parts[0] + $sep + "..." + $sep + ($parts[-3..-1] -join $sep)
    }

    $style = if ($ok) {
        "`e[32m"
    } else {
        "`e[31m"
    }
    "$global:PromptHead`e[36m$path`e[0m $style$global:PromptChar`e[0m `e]133;B`a"
}

# Title while a command runs: its first word (npm, dotnet, ...), as bash does.
# PSReadLine calls this on Enter, just before the line executes; returning its
# default decision keeps the usual history filtering (e.g. of secrets).
#
# Also the OSC 133 "command starts" mark (C), the one shell integration mark
# the prompt function cannot send; see prompt.
Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)
    $command = ($line.TrimStart() -split '\s+', 2)[0]
    if ($command) {
        [Console]::Write("$([char]27)]2;$command$([char]7)$([char]27)]133;C$([char]7)")
        $global:CommandRunning = $true
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
}

<#
.SYNOPSIS
    Switch this shell back to PowerShell's stock prompt (PS C:\path>), e.g. for
    screenshots, recordings or pasting a session somewhere.
.DESCRIPTION
    Also undoes what the custom prompt relies on: PSReadLine's error colouring
    goes back to the stock "> ", and the window title stops following the
    folder and the running command. The theme variables (BAT_THEME,
    DELTA_FEATURES, SYSTEM_COLOR_THEME) keep their last values but no longer
    follow the Windows theme. Only this session is affected; a new shell
    starts with the custom prompt again.
#>
function Disable-Prompt {
    function global:prompt {
        "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
    }

    Set-PSReadLineOption -PromptText '> '
    # Keeps the stock history filtering (e.g. of secrets), only without the title.
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
    }
    $host.UI.RawUI.WindowTitle = [Environment]::ProcessPath
}

if (-not $env:SHELL) {
    $env:SHELL = [Environment]::ProcessPath
}

if ($tools.nvim) {
    $env:EDITOR = "nvim"
}

if ($tools.yazi) {
    $env:YAZI_FILE_ONE = Join-Path $env:ProgramFiles 'Git\usr\bin\file.exe'
}

if ($tools.fnm) {
    # An interactive shell runs it once PowerShell is first idle, i.e. just
    # after the first prompt is drawn, so starting fnm does not delay it.
    # -Command/-File runs never go idle, so they load it right away.
    #
    # The event action runs in a module of its own, and so would every
    # function fnm defines from it, its cd wrapper included. A module keeps
    # its own location history, so `cd -` could not go back past a
    # Set-Location made elsewhere (sd, sdf, y, ...). This script block
    # belongs to the session, being written here, and so does what it
    # defines when the action calls it.
    #
    # fnm puts a junction of its own on PATH for every shell, pointing at the
    # Node version in use. VS Code's server (Remote-SSH, tunnels) turns on
    # Redirection Guard, which the shells in its terminals inherit: they
    # refuse to follow junctions a non-admin made, so `node` is not found.
    # The folder it points to goes first on PATH, at load time and after
    # every `fnm` run, which covers its `fnm use` on cd. The junction stays
    # on PATH as well, since fnm warns on every switch when it is missing.
    $global:FnmExe = $tools.fnm
    $global:FnmInit = {
        & $FnmExe env --use-on-cd | Out-String | Invoke-Expression

        function global:fnm {
            & $FnmExe @args
            Sync-FnmPath
        }

        Sync-FnmPath
    }

    function Sync-FnmPath {
        $dir = $env:FNM_MULTISHELL_PATH

        while ($dir -and ($link = Get-Item -LiteralPath $dir -Force -ErrorAction Ignore).LinkType) {
            $dir = $link.Target
        }

        if (-not $dir -or $dir -eq $global:FnmNodeDir) {
            return
        }

        $rest = $env:PATH -split ';' | Where-Object { $_ -and $_ -ne $global:FnmNodeDir }
        $env:PATH = (@($dir) + $rest) -join ';'
        $global:FnmNodeDir = $dir
    }

    $nonInteractive = [Environment]::GetCommandLineArgs() -match '^-(c|command|f|file|e|ec|encodedcommand)$'

    if ($nonInteractive) {
        & $FnmInit
    } else {
        $null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
            & $global:FnmInit
        }
    }
}

if ($tools.dotnet) {
    # PowerShell parameter completion shim for the dotnet CLI
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, "ParameterValue", $_)
        }
    }
}

<#
.SYNOPSIS
    Resolve the project directory for zj/tm: the given path, or an fzf pick
    from directories under $HOME. Returns nothing when the pick is cancelled.
#>
function Select-ProjectDirectory {
    param(
        [Parameter(Position = 0)]
        [string]$Directory
    )

    if ($Directory) {
        (Resolve-Path -LiteralPath $Directory -ErrorAction Stop).Path
    } else {
        fd --type directory --max-depth 3 --exclude .git --exclude node_modules --exclude .venv --hidden . $HOME |
            fzf --reverse --height=50% `
                --header="select project directory" `
                --border=none `
                --preview-window=border-left `
                --preview "eza --tree --git-ignore --level 2 --colour=always --icons=always {}"
    }
}

function zj {
    param(
        [Parameter(Position = 0)]
        [string]$Directory
    )

    $dir = Select-ProjectDirectory $Directory
    if (-not $dir) {
        return
    }

    $name = (Split-Path -Leaf $dir) -replace '\.', '_'

    if ($env:ZELLIJ) {
        zellij action switch-session $name --cwd $dir
    } else {
        zellij attach --create $name options --default-cwd $dir
    }
}

<#
.SYNOPSIS
    psmux session manager, the psmux twin of zj: switch-client from inside,
    new-session -A (attach or create) from outside.
#>
function tm {
    param(
        [Parameter(Position = 0)]
        [string]$Directory
    )

    $dir = Select-ProjectDirectory $Directory
    if (-not $dir) {
        return
    }

    # TrimEnd: fd prints directories with a trailing separator.
    $name = (Split-Path -Leaf $dir.TrimEnd('\', '/')) -replace '\.', '_'

    # "=" makes -t match the name exactly
    if ($env:TMUX) {
        psmux has-session -t "=$name" 2>$null
        if ($LASTEXITCODE -ne 0) {
            psmux new-session -d -s $name -c $dir
        }
        psmux switch-client -t "=$name"
    } else {
        psmux new-session -A -s $name -c $dir
    }
}

<#
.SYNOPSIS
    psmux (and its tmux alias) with tmux's detach-on-destroy off: when the
    session the client is on ends because its last pane closed, attach to the
    most recently used session left instead of dropping back to this shell.
.DESCRIPTION
    psmux has no detach-on-destroy, and a hook cannot move the client either:
    the server exits right after running it. What psmux does keep is the
    session a client last entered, switches included, in
    ~/.psmux/last_session. If that session still has a port file once the
    client is gone, the client was detached on purpose and the loop stops.
    Only client commands from outside psmux are looped; everything else runs
    as is.
#>
function Invoke-Psmux {
    $exe = (Get-Command psmux -CommandType Application)[0].Source
    $client = -not $env:TMUX -and (
        $args.Count -eq 0 -or
        $args[0] -in 'attach-session', 'attach', 'a', 'at' -or
        ($args[0] -in 'new-session', 'new' -and $args -notcontains '-d'))

    & $exe @args
    if (-not $client) {
        return
    }

    $data = Join-Path $HOME '.psmux'
    while ($true) {
        $last = Get-Content -LiteralPath (Join-Path $data 'last_session') -ErrorAction Ignore
        if (-not $last -or (Test-Path -LiteralPath (Join-Path $data "$last.port"))) {
            return
        }
        & $exe has-session 2>$null
        if ($LASTEXITCODE -ne 0) {
            return
        }
        & $exe attach-session
    }
}

function psmux {
    Invoke-Psmux @args
}
function tmux {
    Invoke-Psmux @args
}

# The user-mode sshd started from ~/.ssh/sshd/sshd_config. Only processes
# started with that config are touched, never a system OpenSSH service.
$global:SshServerConfig = "$env:USERPROFILE\.ssh\sshd\sshd_config"

<#
.SYNOPSIS
    sshd processes started from $SshServerConfig.
#>
function Get-SshServerProcess {
    Get-CimInstance Win32_Process -Filter "Name = 'sshd.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($global:SshServerConfig, [StringComparison]::OrdinalIgnoreCase) }
}

function Start-SshServer {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()

    # The enum, not the 'Administrators' name: group names are localized
    # ('Administradores'), and the string check never matches there.
    $isAdmin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        throw 'Elevated window: SSH sessions would run as administrator. Use a normal window.'
    }
    if (Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue) {
        Write-Warning 'Port 22 is already in use.'; return
    }
    if (-not $PSCmdlet.ShouldProcess($global:SshServerConfig, 'Start sshd')) { return }
    $p = Start-Process "$env:windir\System32\OpenSSH\sshd.exe" -ArgumentList '-f', "`"$global:SshServerConfig`"" -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 500
    if ($p.HasExited) {
        throw "sshd exited (code $($p.ExitCode)). Debug with: sshd -d -f `"$global:SshServerConfig`""
    }
    "sshd started (PID $($p.Id))"
}

function Stop-SshServer {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()

    $processes = @(Get-SshServerProcess)
    if ($processes.Count -eq 0) { return 'sshd not running' }
    foreach ($process in $processes) {
        if ($PSCmdlet.ShouldProcess("sshd $($process.ProcessId)", 'Stop')) {
            Stop-Process -Id $process.ProcessId
        }
    }
    "sshd stopped ($($processes.Count) process(es))"
}

function Get-SshServer {
    $processes = @(Get-SshServerProcess)
    if ($processes.Count -gt 0) {
        $processes | Select-Object @{ n = 'Id'; e = { $_.ProcessId } }, @{ n = 'StartTime'; e = { $_.CreationDate } }
    } else {
        'sshd not running'
    }
}

# fzf, fd, ripgrep, bat, eza, yazi, lazygit and zoxide: key bindings (Ctrl+t,
# Alt+c, Ctrl+r, Ctrl+g, Alt+z) and commands (sf, sd, sg, y, lg, ...). Last,
# because zoxide hooks into the prompt defined above.
. (Join-Path $PSScriptRoot 'CliTools.ps1')