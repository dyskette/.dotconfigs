Set-PSReadLineKeyHandler -Key 'Ctrl+p' -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key 'Ctrl+n' -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key "Ctrl+d" -Function DeleteCharOrExit

function Invoke-Starship-PreCommand {
    # Check for dark mode
    $Value = 'AppsUseLightTheme'
    $Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $UseLight = (Get-ItemProperty -Path $Key -Name $Value  -ErrorAction SilentlyContinue).$Value
    $DarkMode = $false
    If (($UseLight -is [int]) -And ($UseLight -eq 0)) { $DarkMode = $true }

    If ($DarkMode) {
      starship config palette kanagawa_lotus
    }
    else {
      starship config palette kanagawa_wave
    }
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
  $env:STARSHIP_CONFIG = "$HOME\.dotconfigs\starship\config.toml"
  Invoke-Expression (&starship init powershell)
}

if (Get-Command nvim -ErrorAction SilentlyContinue) {
  $env:EDITOR = "nvim"
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
  $env:BAT_THEME="kanagawa-lotus"
  $env:BAT_THEME_DARK="kanagawa-lotus"
  $env:BAT_THEME_LIGHT="kanagawa-wave"
}

if (Get-Command yazi -ErrorAction SilentlyContinue) {
  $env:YAZI_FILE_ONE="C:\Program Files\Git\usr\bin\file.exe"
}

if (Get-Command fnm -ErrorAction SilentlyContinue) {
  fnm env --use-on-cd | Out-String | Invoke-Expression
}

if (Get-Command dotnet -ErrorAction SilentlyContinue) {
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
