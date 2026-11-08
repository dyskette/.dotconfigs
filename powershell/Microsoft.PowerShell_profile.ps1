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
    # its own: set-theme.ps1 reads SYSTEM_COLOR_THEME. A direct registry read,
    # as Get-ItemProperty costs a provider round trip on every prompt.
    if ($IsWindows) {
        $light = [Microsoft.Win32.Registry]::GetValue(
            'HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme', 0)
        $env:SYSTEM_COLOR_THEME = if ($light) {
            'light'
        } else {
            'dark'
        }
    }

    # Report the working directory so the terminal can reopen a tab or
    # split where this one is. OSC 9;9 is ConEmu's, and Windows Terminal
    # honours it.
    #
    # OSC 9;12 ("prompt start") is ConEmu's too, but terminals that read
    # OSC 9 as an iTerm2 toast instead post a notification whose entire body
    # is "12" -- once per prompt. It is therefore emitted only under Windows
    # Terminal, matching the guard bash/bashrc.d/prompt.sh already puts on
    # its own OSC 9;9 line.
    $osc = ""
    if ($env:WT_SESSION) {
        $osc += "`e]9;12`a"
    }
    if ($loc.Provider.Name -eq "FileSystem") {
        $osc += "`e]9;9;`"$($loc.ProviderPath)`"`e\"
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
    "$global:PromptHead`e[36m$path`e[0m $style$global:PromptChar`e[0m "
}

# Title while a command runs: its first word (npm, dotnet, ...), as bash does.
# PSReadLine calls this on Enter, just before the line executes; returning its
# default decision keeps the usual history filtering (e.g. of secrets).
Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)
    $command = ($line.TrimStart() -split '\s+', 2)[0]
    if ($command) {
        [Console]::Write("$([char]27)]2;$command$([char]7)")
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
}

if (-not $env:SHELL) {
    $env:SHELL = [Environment]::ProcessPath
}

if ($tools.nvim) {
    $env:EDITOR = "nvim"
}

if ($tools.yazi) {
    $env:YAZI_FILE_ONE = "C:\Program Files\Git\usr\bin\file.exe"
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

function glog {
    git log --decorate=full --oneline --graph
}

function sd {
    $directory_path = fd --type directory |
        fzf `
            --layout=reverse `
            --height=50% `
            --min-height=20 `
            --preview "eza --tree --git-ignore --level 2 --colour=always --icons=always {}"

    if ($directory_path) {
        Set-Location $directory_path
    }
}

function sf {
    $file_path = fd --type file |
        fzf `
            --layout=reverse `
            --height=50% `
            --min-height=20 `
            --preview "bat --color=always --style=plain {}"

    if ($file_path) {
        nvim $file_path
    }
}

function sdf {
    $file_path = fd --type file |
        fzf `
            --layout=reverse `
            --height=50% `
            --min-height=20 `
            --preview "bat --color=always --style=plain {}"

    if ($file_path) {
        $directory_path = Split-Path -Parent $file_path
        Set-Location $directory_path
    }
}

function sg {
    param (
        [Parameter(ValueFromRemainingArguments = $true)]
        [String[]]$searchParams = ""
    )

    $execRipgrep = "rg --column --color=always --smart-case {q} || :"
    $execNvim = "nvim {1} +{2}"
    $execBat = "bat --style=numbers --color=always --highlight-line {2} {1}"

    fzf `
        --disabled `
        --ansi `
        --bind start:reload:$execRipgrep `
        --bind change:reload:$execRipgrep `
        --bind enter:become:$execNvim `
        --layout reverse `
        --height 50% `
        --min-height 20 `
        --delimiter : `
        --preview $execBat `
        --preview-window "+{2}/2" `
        --query "$([String]::Join(" ", $searchParams))"
}

function y {
    $tmp = [System.IO.Path]::GetTempFileName()
    yazi $args --cwd-file="$tmp"
    $cwd = Get-Content -Path $tmp -Encoding UTF8
    if (-not [String]::IsNullOrEmpty($cwd) -and $cwd -ne $PWD.Path) {
        Set-Location -LiteralPath ([System.IO.Path]::GetFullPath($cwd))
    }
    Remove-Item -Path $tmp
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

function Start-SshServer {
    $cfg = "$env:USERPROFILE\.ssh\sshd\sshd_config"
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
    if ($isAdmin) {
        throw 'Elevated window: SSH sessions would run as administrator. Use a normal window.' 
    }
    if (Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue) {
        Write-Warning 'Port 22 is already in use.'; return
    }
    $p = Start-Process "$env:windir\System32\OpenSSH\sshd.exe" -ArgumentList '-f', "`"$cfg`"" -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 500
    if ($p.HasExited) {
        throw "sshd exited (code $($p.ExitCode)). Debug with: sshd -d -f `"$cfg`"" 
    }
    "sshd started (PID $($p.Id))"
}

function Stop-SshServer {
    Get-Process sshd -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
    'sshd stopped'
}

function Get-SshServer {
    $p = Get-Process sshd -ErrorAction SilentlyContinue
    if ($p) {
        $p | Select-Object Id, StartTime 
    } else {
        'sshd not running' 
    }
}
