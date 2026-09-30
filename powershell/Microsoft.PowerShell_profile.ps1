Set-PSReadLineKeyHandler -Key 'Ctrl+p' -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key 'Ctrl+n' -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key "Ctrl+y" -Function AcceptSuggestion
Set-PSReadLineKeyHandler -Key "Ctrl+d" -Function DeleteCharOrExit

function Invoke-Starship-PreCommand {
    $theme = Get-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name AppsUseLightTheme

    if ($theme.AppsUseLightTheme)
    {
        starship config palette rose-pine-dawn
        $env:BAT_THEME = "rose-pine-dawn"
        $env:SYSTEM_COLOR_THEME = "light"
    } else
    {
        starship config palette gruvbox
        $env:BAT_THEME = "gruvbox"
        $env:SYSTEM_COLOR_THEME = "dark"
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
    $host.ui.Write($prompt)
}

if (Get-Command starship -ErrorAction SilentlyContinue)
{
    $env:STARSHIP_CONFIG = "$HOME\.dotconfigs\starship\config.toml"
    Invoke-Expression (&starship init powershell)
}

if (-not $env:SHELL)
{
    $env:SHELL = (Get-Command pwsh).Source
}

if (Get-Command nvim -ErrorAction SilentlyContinue)
{
    $env:EDITOR = "nvim"
}

if (Get-Command yazi -ErrorAction SilentlyContinue)
{
    $env:YAZI_FILE_ONE = "C:\Program Files\Git\usr\bin\file.exe"
}

if (Get-Command fnm -ErrorAction SilentlyContinue)
{
    fnm env --use-on-cd | Out-String | Invoke-Expression
}

if (Get-Command dotnet -ErrorAction SilentlyContinue)
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

# The WSL shells below load no profile, so ~/.local/bin (where the tmux build
# with the mode 2031 theme hooks lives) is put on PATH by hand; otherwise the
# distro's older /usr/bin/tmux runs and rejects client-dark-theme.
function tmux {
    $command = "export PATH=`$HOME/.local/bin:`$PATH; cd -- && tmux $args"
    wsl --distribution FedoraLinux-42 --exec bash --noprofile -c $command
}

function tmux-pwsh {
    $command = "export PATH=`$HOME/.local/bin:`$PATH; tmux -L pwsh -f `$HOME/.dotconfigs/tmux/pwsh.conf $args"
    wsl --distribution FedoraLinux-42 --exec bash -c $command
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
.NOTES
    Calls psmux, not tmux: the tmux function above is a WSL wrapper.
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
