Set-PSReadLineKeyHandler -Key 'Ctrl+p' -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key 'Ctrl+n' -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key "Ctrl+y" -Function AcceptSuggestion
Set-PSReadLineKeyHandler -Key "Ctrl+d" -Function DeleteCharOrExit

# One PATH scan for every tool the profile wires up, instead of one per tool.
$tools = @{}
Get-Command starship, nvim, yazi, fnm, dotnet -CommandType Application -ErrorAction SilentlyContinue |
    ForEach-Object { $tools[$_.Name -replace '\.exe$', ''] = $_.Source }

function Invoke-Starship-PreCommand {
    $theme = Get-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name AppsUseLightTheme
    $name = if ($theme.AppsUseLightTheme) { "light" } else { "dark" }

    # `starship config palette` starts a second starship and rewrites the
    # config file, so it only runs when the Windows theme actually changed,
    # not before every prompt.
    if ($name -ne $global:StarshipPaletteTheme)
    {
        if ($name -eq "light")
        {
            starship config palette rose-pine-dawn
            $env:BAT_THEME = "rose-pine-dawn"
        } else
        {
            starship config palette gruvbox
            $env:BAT_THEME = "gruvbox"
        }
        $env:SYSTEM_COLOR_THEME = $name
        $global:StarshipPaletteTheme = $name
    }

    # Report the working directory so the terminal can reopen a tab or split
    # where this one is. OSC 9;9 is ConEmu's, and both Windows Terminal and
    # WezTerm honour it.
    #
    # OSC 9;12 ("prompt start") is ConEmu's too, but WezTerm implements OSC 9
    # as an iTerm2 toast instead and has no handler for the 12 subcommand, so
    # it posts a Windows notification whose entire body is "12" -- once per
    # prompt. It is therefore emitted only under Windows Terminal, matching the
    # guard bash/bashrc.d/starship.sh already puts on its own OSC 9;9 line.
    $loc = $executionContext.SessionState.Path.CurrentLocation;
    $prompt = ""
    if ($env:WT_SESSION)
    {
        $prompt += "$([char]27)]9;12$([char]7)"
    }
    if ($loc.Provider.Name -eq "FileSystem")
    {
        $prompt += "$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]27)\"
    }

    # Title at the prompt: the current folder (~ for home), as bash does, so a
    # tab or psmux window reads as where the shell is. Without it the title is
    # pwsh.exe's full path.
    $folder = if ($loc.ProviderPath -eq $HOME) { "~" } else { Split-Path -Leaf $loc.ProviderPath }
    $prompt += "$([char]27)]2;$folder$([char]7)"
    $host.ui.Write($prompt)
}

# Title while a command runs: its first word (npm, dotnet, ...), as bash does.
# PSReadLine calls this on Enter, just before the line executes; returning its
# default decision keeps the usual history filtering (e.g. of secrets).
Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)
    $command = ($line.TrimStart() -split '\s+', 2)[0]
    if ($command)
    {
        [Console]::Write("$([char]27)]2;$command$([char]7)")
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
}

if ($tools.starship)
{
    $env:STARSHIP_CONFIG = "$HOME\.dotconfigs\starship\config.toml"

    # The theme the config's palette already matches, so the first prompt of
    # a shell does not rewrite it either.
    $palette = (Select-String -LiteralPath $env:STARSHIP_CONFIG -Pattern '^palette = "(.+)"' -List).Matches.Groups[1].Value
    $global:StarshipPaletteTheme = switch ($palette) { "rose-pine-dawn" { "light" } "gruvbox" { "dark" } }
    if ($global:StarshipPaletteTheme)
    {
        $env:SYSTEM_COLOR_THEME = $global:StarshipPaletteTheme
        $env:BAT_THEME = $palette
    }

    # `starship init powershell` only prints a line that runs starship again
    # for the full script, so every shell paid for two starship processes and
    # an Invoke-Expression. The full script is cached instead, and rebuilt
    # whenever starship.exe is newer than the cache (i.e. after an update).
    $starshipInit = Join-Path $env:LOCALAPPDATA "starship\init.ps1"
    $initFile = Get-Item -LiteralPath $starshipInit -ErrorAction SilentlyContinue
    if (-not $initFile -or $initFile.LastWriteTime -lt (Get-Item -LiteralPath $tools.starship).LastWriteTime)
    {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $starshipInit)
        & $tools.starship init powershell --print-full-init | Set-Content -LiteralPath $starshipInit -Encoding utf8
    }
    . $starshipInit
}

if (-not $env:SHELL)
{
    $env:SHELL = [Environment]::ProcessPath
}

if ($tools.nvim)
{
    $env:EDITOR = "nvim"
}

if ($tools.yazi)
{
    $env:YAZI_FILE_ONE = "C:\Program Files\Git\usr\bin\file.exe"
}

if ($tools.fnm)
{
    # An interactive shell runs it once PowerShell is first idle, i.e. just
    # after the first prompt is drawn, so starting fnm does not delay it.
    # Everything fnm defines is global: or $env:, so running from the event
    # action changes nothing else. -Command/-File runs never go idle, so they
    # load it right away.
    $nonInteractive = [Environment]::GetCommandLineArgs() -match '^-(c|command|f|file|e|ec|encodedcommand)$'
    if ($nonInteractive)
    {
        fnm env --use-on-cd | Out-String | Invoke-Expression
    } else
    {
        $null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
            fnm env --use-on-cd | Out-String | Invoke-Expression
        }
    }
}

if ($tools.dotnet)
{
    # PowerShell parameter completion shim for the dotnet CLI
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, "ParameterValue", $_)
        }
    }
}

function glog
{
    git log --decorate=full --oneline --graph
}

function sd
{
    $directory_path = fd --type directory |
        fzf `
            --layout=reverse `
            --height=50% `
            --min-height=20 `
            --preview "eza --tree --git-ignore --level 2 --colour=always --icons=always {}"

    if ($directory_path)
    {
        Set-Location $directory_path
    }
}

function sf
{
    $file_path = fd --type file |
        fzf `
            --layout=reverse `
            --height=50% `
            --min-height=20 `
            --preview "bat --color=always --style=plain {}"

    if ($file_path)
    {
        nvim $file_path
    }
}

function sdf
{
    $file_path = fd --type file |
        fzf `
            --layout=reverse `
            --height=50% `
            --min-height=20 `
            --preview "bat --color=always --style=plain {}"

    if ($file_path)
    {
        $directory_path = Split-Path -Parent $file_path
        Set-Location $directory_path
    }
}

function sg
{
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

function y
{
    $tmp = [System.IO.Path]::GetTempFileName()
    yazi $args --cwd-file="$tmp"
    $cwd = Get-Content -Path $tmp -Encoding UTF8
    if (-not [String]::IsNullOrEmpty($cwd) -and $cwd -ne $PWD.Path)
    {
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

    if ($Directory)
    {
        (Resolve-Path -LiteralPath $Directory -ErrorAction Stop).Path
    } else
    {
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
    if (-not $dir)
    {
        return
    }

    $name = (Split-Path -Leaf $dir) -replace '\.', '_'

    if ($env:ZELLIJ)
    {
        zellij action switch-session $name --cwd $dir
    } else
    {
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
    if (-not $dir)
    {
        return
    }

    # TrimEnd: fd prints directories with a trailing separator.
    $name = (Split-Path -Leaf $dir.TrimEnd('\', '/')) -replace '\.', '_'

    # "=" makes -t match the name exactly
    if ($env:TMUX)
    {
        psmux has-session -t "=$name" 2>$null
        if ($LASTEXITCODE -ne 0)
        {
            psmux new-session -d -s $name -c $dir
        }
        psmux switch-client -t "=$name"
    } else
    {
        psmux new-session -A -s $name -c $dir
    }
}
