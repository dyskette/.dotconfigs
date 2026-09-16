--- The discoverable keymap reference.
---
--- WezTerm has no which-key popup, so a cheat sheet is what turns a configured
--- system into a used one. Rendered to a file and opened in a new tab.

local wezterm = require("wezterm")

local util = require("wf_util")

local M = {}

local TEXT = [[
# WezTerm workflow — keymap

Leader is `Ctrl+b`. `LEADER LEADER` sends a literal Ctrl+b through, so a
remote tmux (prefix `Ctrl+a`) and readline still receive it.

Keys below are shown for the Latin American ISO layout. Where that layout
differs from US, the LATAM column says how to type it.

## No prefix

| Key | Action |
|---|---|
| `Ctrl+h/j/k/l`       | Move pane focus — falls through to Neovim splits |
| `Ctrl+Shift+h/j/k/l` | Resize active pane |
| `Ctrl+Shift+c/v`     | Copy / paste |
| `Ctrl+Shift+f`       | Search scrollback |
| `Shift+PageUp/Dn`    | Scroll by page |

## Projects and workspaces

| Key | Action |
|---|---|
| `LEADER f`   | Find project in *this pane's* environment |
| `LEADER F`   | Rescan this environment's roots, then pick |
| `LEADER w`   | Switch between open workspaces only |
| `LEADER Tab` | Toggle last workspace |
| `LEADER n`   | Jump to @notes |
| `LEADER .`   | Jump to @scratch |
| `LEADER W`   | Rename current workspace |
| `LEADER X`   | Close workspace and all its tabs |

## Tabs

| Key | Action |
|---|---|
| `LEADER e`     | edit tab |
| `LEADER r`     | run tab |
| `LEADER a`     | agent tab |
| `LEADER d`     | notes tab |
| `LEADER 1…9`   | Tab by index |
| `LEADER [ ]`   | Previous / next tab  — Shift on LATAM, same keys as `{ }` |
| `LEADER t`     | New tab |
| `LEADER ,`     | Rename tab |
| `LEADER Q`     | Close tab |

Named tabs recreate themselves from the template if you closed them.

## Panes

| Key | Action |
|---|---|
| `LEADER |`      | Split right  — `|` is unshifted on LATAM (left of 1) |
| `LEADER \`      | Split right  — alias, needs AltGr on LATAM |
| `LEADER -`      | Split down |
| `LEADER Space`  | PaneSelect — jump by label |
| `LEADER s`      | PaneSelect — swap mode |
| `LEADER z`      | Zoom / unzoom |
| `LEADER x`      | Close pane |
| `LEADER !`      | Break pane out into its own tab |
| `LEADER R`      | Resize mode: h/j/k/l, HJKL for big steps, Esc to exit |
| `LEADER =`      | Rebalance panes  — `=` is Shift+0 on LATAM |
| `LEADER +`      | Rebalance panes  — `+` is unshifted on LATAM |

## Copy, search, yank

| Key | Action |
|---|---|
| `LEADER v`   | Copy mode (vim motions, `y` yanks) |
| `LEADER /`   | Copy mode, seeded into search  — `/` is Shift+7 on LATAM |
| `LEADER c`   | QuickSelect — label a token, press it, copied |
| `LEADER C`   | QuickSelect and open (URL / file) |
| `LEADER y`   | Copy the entire output of the last command |
| `LEADER Y`   | Dump scrollback to a file and open it |
| `LEADER p`   | Paste |
| `LEADER { }` | Jump to previous / next shell prompt  — unshifted on LATAM |

`LEADER y` and prompt jumping need the OSC 133 shell integration
(`bash/bashrc.d/wezterm-shell-integration.sh`).

## Meta

| Key | Action |
|---|---|
| `LEADER ?`            | This cheat sheet |
| `LEADER Ctrl+r`       | Reload config |
| `LEADER Ctrl+l`       | Clear scrollback and screen |
| `LEADER Enter`        | Where → what: pick an environment, then a shell or project |
| `LEADER Shift+Enter`  | WezTerm's own launcher (domains + launch menu) |
]]

--- Writes the cheat sheet next to the other generated files and opens it in a
--- new tab, read-only.
function M.show()
  return wezterm.action_callback(function(window, pane)
    local path = util.cache_dir() .. "/wezterm-cheatsheet.md"

    local handle = io.open(path, "w")
    if not handle then
      window:toast_notification("wezterm", "Could not write " .. path, nil, 4000)
      return
    end
    handle:write(TEXT)
    handle:close()

    local tab = window:mux_window():spawn_tab(util.view_file_opts(pane, path))
    tab:set_title("help")
  end)
end

return M
