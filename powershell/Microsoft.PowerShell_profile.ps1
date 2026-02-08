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
        starship config palette adwaita
        $env:BAT_THEME = "adwaita"
        $env:SYSTEM_COLOR_THEME = "dark"
    }
}

if (Get-Command starship -ErrorAction SilentlyContinue)
{
    $env:STARSHIP_CONFIG = "$HOME\.dotconfigs\starship\config.toml"
    Invoke-Expression (&starship init powershell)
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

function tmux {
    $command = "cd -- && tmux $args"
    wsl --distribution Ubuntu-24.04 --exec bash --noprofile -c $command
}

function tmux-pwsh {
    $command = "tmux -L pwsh -f `$HOME/.dotconfigs/tmux/pwsh.conf $args"
    wsl --distribution Ubuntu-24.04 --exec bash -c $command
}
