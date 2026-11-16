# Configuration

## Windows

In PowerShell, as your normal user:

```powershell
irm https://raw.githubusercontent.com/dyskette/.dotconfigs/master/windows/Bootstrap.ps1 | iex
```

Details, re-running, troubleshooting and development: [windows/README.md](windows/README.md).

## Linux

```bash
curl -sSL https://raw.githubusercontent.com/dyskette/.dotconfigs/refs/heads/master/linux/install.sh | bash
```

## Command-line tools

fzf, fd, ripgrep, bat, eza, yazi, lazygit, delta and zoxide share one set of
defaults, read the same way by PowerShell (`powershell/CliTools.ps1`), bash
(`bash/bashrc.d/fzf.sh`, `files.sh`, `zoxide.sh`), yazi and nvim:

| File | Read through |
| --- | --- |
| `fzf/fzfrc` | `FZF_DEFAULT_OPTS_FILE` |
| `ripgrep/config` | `RIPGREP_CONFIG_PATH` (nvim sets it too, for `:grep`) |
| `fd/ignore` | linked to `~/.config/fd/ignore`, `%APPDATA%\fd\ignore` |
| `bat/config` | linked |
| `delta/everforest.gitconfig` | linked to `~/.config/delta`, pulled into the global git config with `include.path`; callers pick `--features=everforest-light\|dark` |

Colours are ANSI everywhere, so they follow the terminal's light/dark theme.
The exception is bat and delta, which need a named theme. They work it out by
asking the terminal for its background colour, which only works where they are
the program holding it: inside an fzf preview or lazygit another one is, and it
takes the reply. So each shell asks once at startup and passes the answer on —
bash through `BAT_THEME` (`bash/bashrc.d/colors.sh`), PowerShell through
`BAT_THEME` and `SYSTEM_COLOR_THEME`, read from the Windows registry at every
prompt. In bash, `theme [light|dark]` re-detects or forces it in a shell
already open.

Same keys and commands in both shells:

| | |
| --- | --- |
| `Ctrl+t` / `Alt+c` / `Ctrl+r` | insert files / cd into a folder / history, with fzf |
| `sf` `sd` `sdf` | pick files to edit / a folder to enter / a file whose folder to enter |
| `sg [pattern]` | live ripgrep; `Ctrl+f` fuzzy-filters the hits; Enter opens in nvim, several (Tab) as quickfix |
| `y` / `lg` | yazi / lazygit, staying in the folder they were left in |
| `gsw` / `glo` | switch branch / browse the log with delta diffs |
| `z` / `zi` | zoxide jump / pick |
| `ls ll la lt` / `cat` | eza / bat |
| `theme [light\|dark]` | re-detect or force the colour scheme for this shell |

In nvim, `<leader>gg` toggles lazygit and `<C-\>` a shell, both in floats
(toggleterm.nvim). Anything they open with `nvim` (lazygit's `e`, a commit
message, `sf`, `sg`) lands in that nvim (flatten.nvim), not a nested one. In
tmux/psmux, `prefix g` and `prefix e` open lazygit and yazi over the pane.

## Sessions (tmux and psmux)

A session per project. The pickers are the same bash scripts on both
(`tmux/scripts`, run by Git Bash on Windows):

| | |
| --- | --- |
| `prefix s` / `tm` | switch session or open a project: first the folders with a session (●), most recent first; then the ones declared in `tmux/projects.conf`, the folders inside its roots, and zoxide's 30 most used |
| `tm DIR` | open DIR's session |
| `prefix a` | walk to any folder, one level at a time, and open a session there |
| `prefix w` | switch window, most recent first; `ctrl-x` twice closes one |

`tmux/projects.conf` serves both machines: paths that do not exist are
skipped, so it lists the Windows roots (`~/Projects`, `~/source/repos`) and the
Linux one (`~/Proyectos`) side by side. A session opened on a folder is the one
already running there, or a new one named after the folder (or the name
declared for it). A session started from a plain terminal asks for a project
first and replaces itself with that project's session.

Zellij is back to a bare config (`zellij/config.kdl`, one file for both
machines): the stock modes, reached with `Alt a` instead of `Ctrl g`, and the
Everforest theme. The workspace that used to be built on top of it — a session
per repo, a tab per activity, a session hub — is gone; its Zellij plugin is
parked in [pilot/](pilot/README.md), and session switching is tmux's job for
now (`s`, `bash/bashrc.d/sesh.sh`).
