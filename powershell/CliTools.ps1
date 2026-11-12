#Requires -Version 7
# The command-line tools wired into the interactive shell: fzf, fd, ripgrep,
# bat, eza, yazi, lazygit, delta and zoxide. Dot-sourced by the profile, so
# everything defined here lands in the global scope like the profile's own.
#
# Key bindings (PSReadLine):
#   Ctrl+t   insert files picked with fzf (bat preview) at the cursor
#   Alt+c    cd into a folder picked with fzf (eza tree preview)
#   Ctrl+r   search history with fzf, multi-line commands included
#   Ctrl+g   live ripgrep, open the hits in nvim
#   Alt+z    jump to a frequent folder (zoxide)
#
# Commands: sf sd sdf sg y lg gsw glo, ls ll la lt (eza), cat (bat), z zi
# (zoxide). Each one explains itself with Get-Help.
#
# fzf runs its previews and reloads through cmd.exe here, never pwsh: every
# cursor move starts one, and pwsh -NoProfile takes ~390 ms to do it where
# cmd.exe takes ~70 ms. So the commands in --preview/--bind below are written
# for cmd (and happen to be valid sh as well).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
    Justification = "zoxide's documented PowerShell integration is 'zoxide init powershell | Invoke-Expression'.")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '',
    Justification = 'ls and cat are aliases, replaced on purpose in the interactive shell only; piped, they fall back to the cmdlets.')]
param()

$dotconfigs = Join-Path $HOME '.dotconfigs'

$env:FZF_DEFAULT_OPTS_FILE = Join-Path $dotconfigs 'fzf\fzfrc'
$env:RIPGREP_CONFIG_PATH = Join-Path $dotconfigs 'ripgrep\config'
# cmd.exe for fzf's own commands, as explained above. Explicit --with-shell
# flags (the tmux switchers pass their own) still win.
$env:FZF_DEFAULT_OPTS = '--with-shell="cmd.exe /d /s /c"'
$env:FZF_DEFAULT_COMMAND = 'fd --type file --hidden --follow --strip-cwd-prefix'

# Previews, written once and shared by the key bindings and the commands.
$script:FzfPreviewFile = 'bat --color=always --style=numbers,changes --line-range=:500 {}'
$script:FzfPreviewDir = 'eza --tree --level=2 --color=always --icons=always --group-directories-first --git-ignore {}'

<#
.SYNOPSIS
    Run fzf over native input and return the picked lines, or nothing when it
    was cancelled.
.PARAMETER Source
    The command that lists the candidates, as a script block, so its output
    goes to fzf as raw bytes (native-to-native pipe) instead of strings.
.PARAMETER FzfOption
    fzf's arguments.
#>
function Invoke-Fzf {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Source,

        [string[]]$FzfOption = @()
    )

    # $Source runs in this scope, so its variables must not collide with
    # these parameters' names.
    $picked = & $Source | fzf @FzfOption
    if ($LASTEXITCODE -eq 0) {
        $picked
    }
}

<#
.SYNOPSIS
    Quote a path for the command line when it needs it.
#>
function ConvertTo-ShellPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -match "[\s'`"`$``;&(){}|<>,@]") {
        "'" + $Path.Replace("'", "''") + "'"
    } else {
        $Path
    }
}

<#
.SYNOPSIS
    Repaint the prompt after a key binding ran fzf below it, or changed folder.
#>
function Invoke-ReadLinePrompt {
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}

# --- Files and folders -------------------------------------------------------

<#
.SYNOPSIS
    Pick files with fzf (bat preview) and open them in nvim.
.PARAMETER Query
    Initial fzf query.
#>
function sf {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Query)

    # @(): one pick is a bare string, and splatting a string passes its first
    # character.
    $files = @(Invoke-Fzf { fd --type file --hidden --follow --strip-cwd-prefix } @(
            '--multi', '--scheme=path', "--query=$Query",
            '--border-label= files ', "--preview=$FzfPreviewFile"))
    if ($files) {
        nvim @files
    }
}

<#
.SYNOPSIS
    Pick a folder below the current one with fzf (eza tree preview) and cd
    into it.
.PARAMETER Query
    Initial fzf query.
#>
function sd {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Query)

    $dir = Invoke-Fzf { fd --type directory --hidden --follow --strip-cwd-prefix } @(
        '--scheme=path', "--query=$Query", "--preview=$FzfPreviewDir")
    if ($dir) {
        Set-Location -LiteralPath $dir
    }
}

<#
.SYNOPSIS
    Pick a file with fzf and cd into its folder.
.PARAMETER Query
    Initial fzf query.
#>
function sdf {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Query)

    $file = Invoke-Fzf { fd --type file --hidden --follow --strip-cwd-prefix } @(
        '--scheme=path', "--query=$Query", "--preview=$FzfPreviewFile")
    if ($file) {
        Set-Location -LiteralPath (Split-Path -Parent ([IO.Path]::GetFullPath($file)))
    }
}

<#
.SYNOPSIS
    Live ripgrep in fzf; Enter opens the hit in nvim at its line, several
    selected hits (Tab) open as nvim's quickfix list.
.DESCRIPTION
    Typing re-runs ripgrep. Ctrl+f freezes the ripgrep results and switches
    to fuzzy-filtering them with fzf; Ctrl+r goes back to ripgrep. Inside a
    nvim terminal the files open in that nvim (flatten.nvim).
.PARAMETER Query
    Initial ripgrep pattern.
#>
function sg {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Query)

    $rg = 'rg --column --line-number --no-heading --color=always -- {q}'
    $hits = Invoke-Fzf { $null } @(
        '--ansi', '--disabled', '--multi', "--query=$Query",
        '--delimiter=:', '--prompt=rg ❯ ',
        '--border-label= ripgrep ',
        '--header=ctrl-f fuzzy-filter these · ctrl-r back to ripgrep · tab select',
        "--bind=start:reload($rg)+unbind(ctrl-r)",
        "--bind=change:reload($rg)",
        '--bind=ctrl-f:unbind(change,ctrl-f)+change-prompt(fzf ❯ )+enable-search+clear-query+rebind(ctrl-r)',
        "--bind=ctrl-r:unbind(ctrl-r)+change-prompt(rg ❯ )+disable-search+reload($rg)+rebind(change,ctrl-f)",
        '--preview=bat --color=always --style=numbers,changes,header-filename --highlight-line={2} {1}',
        '--preview-window=+{2}/2')
    Open-GrepHit $hits
}

<#
.SYNOPSIS
    Open ripgrep hits (file:line:column:text) in nvim: one at its line,
    several as the quickfix list.
#>
function Open-GrepHit {
    param([string[]]$Hit)

    if (-not $Hit) {
        return
    }
    if ($Hit.Count -eq 1) {
        $file, $line = $Hit[0] -split ':', 3
        nvim $file "+$line"
        return
    }

    # :QuickfixLoad (nvim/lua/config/terminals.lua) reads file:line:col:text
    # and opens the list. Not `nvim -q`, which flatten.nvim hands to the outer
    # nvim without showing it. The list is read before nvim returns, so the
    # file can go right after.
    $list = New-TemporaryFile
    try {
        Set-Content -LiteralPath $list -Value $Hit -Encoding utf8NoBOM
        nvim "+QuickfixLoad $list"
    } finally {
        Remove-Item -LiteralPath $list -ErrorAction Ignore
    }
}

<#
.SYNOPSIS
    yazi, cd-ing to the folder it was left in.
#>
function y {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        yazi @args --cwd-file="$tmp"
        $cwd = Get-Content -LiteralPath $tmp -Encoding utf8
        if (-not [string]::IsNullOrEmpty($cwd) -and $cwd -ne $PWD.Path) {
            Set-Location -LiteralPath ([IO.Path]::GetFullPath($cwd))
        }
    } finally {
        Remove-Item -LiteralPath $tmp -ErrorAction Ignore
    }
}

# --- eza and bat in place of ls and cat --------------------------------------
# Only at the end of a pipeline: `ls | Where-Object ...` and
# `cat file | ConvertFrom-Json` still get the cmdlets' objects and text.

Remove-Item -Path Alias:ls, Alias:cat -Force -ErrorAction Ignore

<#
.SYNOPSIS
    True when the calling command's output goes on down a pipeline.
#>
function Test-Piped {
    param([Parameter(Mandatory)][Management.Automation.InvocationInfo]$Invocation)

    $Invocation.PipelinePosition -lt $Invocation.PipelineLength
}

<#
.SYNOPSIS
    eza (folders first, icons, git status); Get-ChildItem when piped.
#>
function ls {
    if (Test-Piped $MyInvocation) {
        Get-ChildItem @args
    } else {
        eza --group-directories-first --icons=auto --hyperlink @args
    }
}

<#
.SYNOPSIS
    Long listing with git status and headers, dotfiles included.
#>
function ll {
    eza --long --all --group-directories-first --icons=auto --git --header --time-style=relative --hyperlink @args
}

<#
.SYNOPSIS
    Everything, dotfiles included, in a grid.
#>
function la {
    eza --all --group-directories-first --icons=auto --hyperlink @args
}

<#
.SYNOPSIS
    Tree view, gitignored files left out. lt 3 goes three levels deep.
.PARAMETER Level
    Depth of the tree.
#>
function lt {
    param(
        [Parameter(Position = 0)][int]$Level = 2,
        [Parameter(ValueFromRemainingArguments)][string[]]$Rest
    )

    eza --tree --level=$Level --group-directories-first --icons=auto --git-ignore @Rest
}

<#
.SYNOPSIS
    bat with syntax colours and no pager or decorations; Get-Content when
    piped.
#>
function cat {
    if (Test-Piped $MyInvocation) {
        Get-Content @args
    } else {
        bat --paging=never --style=plain @args
    }
}

# --- Git ---------------------------------------------------------------------

function glog {
    git log --decorate=full --oneline --graph
}

<#
.SYNOPSIS
    lazygit, cd-ing to the repository it was left in (after switching repos
    from its recent list).
#>
function lg {
    $tmp = [IO.Path]::GetTempFileName()
    $env:LAZYGIT_NEW_DIR_FILE = $tmp
    try {
        lazygit @args
        $dir = Get-Content -LiteralPath $tmp -Encoding utf8 -ErrorAction Ignore
        if ($dir -and $dir -ne $PWD.Path) {
            Set-Location -LiteralPath $dir
        }
    } finally {
        Remove-Item Env:LAZYGIT_NEW_DIR_FILE -ErrorAction Ignore
        Remove-Item -LiteralPath $tmp -ErrorAction Ignore
    }
}

<#
.SYNOPSIS
    Switch branch: pick a local or remote branch, newest first, with its log
    in the preview. A remote one gets a local tracking branch.
#>
function gsw {
    $branch = Invoke-Fzf {
        git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads refs/remotes
    } @(
        '--scheme=history', '--no-multi', '--border-label= branches ',
        '--preview=git log --oneline --graph --color=always --decorate -n 50 {}')
    if (-not $branch) {
        return
    }
    if ($branch -match '^[^/]+/(.+)$' -and -not (git rev-parse --verify --quiet "refs/heads/$branch")) {
        # origin/feature -> feature, tracking origin/feature (git switch's
        # --guess does this when only one remote has the branch).
        git switch $Matches[1] 2>$null
        if ($LASTEXITCODE -eq 0) {
            return
        }
    }
    git switch $branch
}

<#
.SYNOPSIS
    Browse the log with fzf, each commit's diff (delta) in the preview. The
    picked commits' hashes go to the pipeline.
.PARAMETER LogArgument
    Passed to git log (a range, a path, --all, ...).
#>
function glo {
    param([Parameter(ValueFromRemainingArguments)][string[]]$LogArgument)

    $commits = git log --color=always --date=short @LogArgument `
        --format='%C(yellow)%h%C(reset) %C(green)%ad%C(reset) %s%C(auto)%d %C(blue)%an' |
        fzf --ansi --multi --no-sort --scheme=history --border-label=' log ' `
            --preview='git show --color=always {1} | delta --width=%FZF_PREVIEW_COLUMNS%' `
            --preview-window='down,70%,border-top'
    if ($LASTEXITCODE -ne 0) {
        return
    }
    foreach ($commit in $commits) {
        ($commit -split ' ', 2)[0]
    }
}

# --- Key bindings ------------------------------------------------------------

Set-PSReadLineKeyHandler -Chord 'Ctrl+t' -BriefDescription 'FzfFiles' -Description 'Insert files picked with fzf' -ScriptBlock {
    $files = Invoke-Fzf { fd --type file --hidden --follow --strip-cwd-prefix } @(
        '--multi', '--scheme=path', '--border-label= files ', "--preview=$FzfPreviewFile")
    if ($files) {
        $text = ($files | ForEach-Object { ConvertTo-ShellPath $_ }) -join ', '
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($text)
    }
    Invoke-ReadLinePrompt
}

Set-PSReadLineKeyHandler -Chord 'Alt+c' -BriefDescription 'FzfCd' -Description 'cd into a folder picked with fzf' -ScriptBlock {
    $dir = Invoke-Fzf { fd --type directory --hidden --follow --strip-cwd-prefix } @(
        '--scheme=path', '--border-label= cd ', "--preview=$FzfPreviewDir")
    if ($dir) {
        Set-Location -LiteralPath $dir
    }
    Invoke-ReadLinePrompt
}

Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -BriefDescription 'FzfHistory' -Description 'Search history with fzf' -ScriptBlock {
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    # PSReadLine saves a multi-line command one line per line, each but the
    # last ending in a backtick. Rebuild them, newest first, without repeats.
    $entries = [Collections.Generic.List[string]]::new()
    $pending = [Text.StringBuilder]::new()
    foreach ($text in [IO.File]::ReadLines((Get-PSReadLineOption).HistorySavePath)) {
        if ($text.EndsWith('`')) {
            [void]$pending.Append($text, 0, $text.Length - 1).Append("`n")
        } else {
            $entries.Add($pending.Append($text).ToString())
            [void]$pending.Clear()
        }
    }
    $seen = [Collections.Generic.HashSet[string]]::new()
    $unique = for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        if ($entries[$i].Trim() -and $seen.Add($entries[$i])) {
            $entries[$i]
        }
    }

    # NUL-separated both ways, so a multi-line command stays one entry, shown
    # whole (fzf draws --read0 items on several lines).
    $picked = ($unique -join "`0") | fzf --read0 --print0 --scheme=history --no-multi `
        --border-label=' history ' --query=$line
    if ($LASTEXITCODE -eq 0 -and $picked) {
        $command = ($picked -join "`n").TrimEnd([char]0)
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $command)
    }
    Invoke-ReadLinePrompt
}

Set-PSReadLineKeyHandler -Chord 'Ctrl+g' -BriefDescription 'FzfGrep' -Description 'Live ripgrep, open hits in nvim' -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert('sg')
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# --- zoxide ------------------------------------------------------------------
# z jumps to the best match of its arguments, zi picks with fzf. Loaded last:
# its hook wraps the prompt the profile defined. Alt+z is zi from the prompt.

if (Get-Command zoxide -CommandType Application -ErrorAction Ignore) {
    zoxide init powershell | Out-String | Invoke-Expression

    Set-PSReadLineKeyHandler -Chord 'Alt+z' -BriefDescription 'ZoxideInteractive' -Description 'Jump to a frequent folder (zoxide + fzf)' -ScriptBlock {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert('zi')
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}
