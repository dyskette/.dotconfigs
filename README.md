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

Colours are ANSI everywhere, so they follow the terminal's light/dark theme.

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

In nvim, `<leader>gg` toggles lazygit and `<C-\>` a shell, both in floats
(toggleterm.nvim). Anything they open with `nvim` (lazygit's `e`, a commit
message, `sf`, `sg`) lands in that nvim (flatten.nvim), not a nested one. In
tmux/psmux, `prefix g` and `prefix e` open lazygit and yazi over the pane.
