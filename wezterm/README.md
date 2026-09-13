# WezTerm workflow system

A project-oriented terminal for switching between client repos many times a day.

```
WORKSPACE  = a project = one git repo          → "billing-api"
  └ TAB    = an activity inside that project   → edit / run / agent / notes
      └ PANE = a surface inside that activity  → shell, server log, agent
```

Leader is `Ctrl+b`. Press `LEADER ?` for the full keymap.

`Ctrl+Space` was the spec's choice but is unusable here: it is the Japanese IME
toggle on Windows and the Japanese layout is installed. `Ctrl+a` is out too —
that is the tmux prefix in `tmux/tmux.conf`, and the local multiplexer must not
collide with the remote one. `Ctrl+b` costs readline `backward-char` and
Neovim's page-up; both have arrow/PageUp equivalents. Move it in
`wf_settings.lua` (`M.leader`).

## Files

| File | Responsibility |
|---|---|
| `wezterm.lua`       | Entry point: domains, appearance, leader, wiring |
| `wf_settings.lua`   | **Everything you are expected to tune** |
| `wf_shells.lua`     | Shell/domain chooser at startup and on LEADER Enter |
| `wf_util.lua`       | Platform differences, shell execution, path and color math |
| `wf_theme.lua`      | Light/dark theme selection |
| `wf_projects.lua`   | Repo discovery, pickers, the layout template |
| `wf_status.lua`     | Status bar, tab titles, client accents, prod warnings |
| `wf_keys.lua`       | Keymap and the resize key table |
| `wf_cheatsheet.lua` | `LEADER ?` |
| `<theme>.lua`       | Color schemes (unchanged) |

Files are flat on purpose: `Configure-Dotfiles.ps1` links `wezterm\*.lua` as a
glob, so a subdirectory would silently not be linked.

## Setup

1. **Link the new files.** `windows\Configure-Dotfiles.ps1` (or the full
   installer). The glob picks up the new `wf_*.lua` automatically.
2. **Set your repo roots** in `wf_settings.lua` — `repo_roots` currently guesses
   `~/code`, `~/work`, `~/dev`. Nothing works until these are right.
3. **Neovim**: `nvim/lua/plugins/wezterm-nav.lua` adds `smart-splits.nvim` and
   publishes `IS_NVIM` so `Ctrl+hjkl` crosses the editor/terminal boundary.
   Note the leader shadows `<C-b>` inside Neovim (page-up, and blink's
   documentation scroll); use `PageUp` and `<C-f>`.
4. **Shell**: `bash/bashrc.d/wezterm-shell-integration.sh` emits OSC 133 and
   OSC 7. Without it `LEADER y`, `LEADER { }` and the git status field do not
   exist, and new splits do not inherit the current directory.
5. Open a new WezTerm and press `LEADER f`.

## Shells: Windows or WSL

Consulting is not single-platform — some clients are Windows top to bottom,
others are mixed and covered through WSL. So the choice is presented rather
than assumed:

- **When a window opens**, a fuzzy picker lists the shells. `Escape` keeps the
  default (WSL), so the common case costs one keystroke — or none, if you just
  start typing in the pane behind it.
- **`LEADER Enter`** brings the same list up any time, for a tab on the other
  platform.
- Picking the shell that is already running is a no-op; picking a different one
  opens it and drops the placeholder tab, so you never end up with a spare.

Tabs and splits made from a pane inherit its domain, so a window stays on one
platform until you ask otherwise. Edit `shells_windows` / `shells_unix` in
`wf_settings.lua` to change the list, or set `startup_shell_picker = false` to
go straight to the default.

Helper tabs follow the pane they were invoked from: `LEADER ?` and `LEADER Y`
open in the current pane's domain, so pressing them in a PowerShell pane uses
Windows `nvim` and never starts the WSL VM just to display a file.

WezTerm's own launcher (`LEADER Shift+Enter`) lists the same entries plus every
registered domain — useful for confirming a domain name if a shell reports one
as unknown.

**Known gap:** the project system (`LEADER f`) is WSL-only. Its roots are WSL
paths and the scan runs through WSL, so a Windows-native client repo will not
appear. Windows-side projects currently mean `LEADER Enter` plus a manual `cd`.

## Latin American ISO layout

Adapted from `latam(basic)` in `/usr/share/X11/xkb/symbols/latam` (Windows KLID
`0000080a`). What changes versus a US keyboard:

| Need | How to type it on LATAM | Used for |
|---|---|---|
| `\` | AltGr + `'` | split right (alias only, too expensive to be primary) |
| <code>&#124;</code> | unshifted, left of `1` | **split right** |
| `{` `}` | **unshifted** | prompt jumps — the cheap pair on this layout |
| `[` `]` | Shift | prev/next tab — same two physical keys as `{` `}` |
| `+` | unshifted | rebalance |
| `=` | Shift + `0` | rebalance (alias) |
| `/` | Shift + `7` | search; `Ctrl+Shift+f` needs no prefix |

**AltGr protection matters most.** On Windows AltGr reports as Ctrl+Alt, and
WezTerm's stock `Ctrl+Alt` assignments sit on `'`, `"`, `%` and `5` — exactly
the keys LATAM uses AltGr with to produce `\`, `{`, `}`, `[`, `]` and `~`. Those four defaults
are turned off with `DisableDefaultAssignment`, so typing a backslash no longer
splits a pane. Right Alt composes characters; left Alt stays a modifier.

Dead keys stay on so `´` and `¨` compose Spanish accents; set
`use_dead_keys = false` in `wezterm.lua` if you would rather they emit
immediately.

## Tuning

Common edits, all in `wf_settings.lua`:

- `repo_roots`, `scan_depth` — where projects are found
- `agent_cmd`, `editor` — what the template launches
- `template_splits` — pane proportions, used both when building and rebalancing
- `prod_patterns` — what turns the frame red
- `client_colors` — the accent palette
- `quick_select_patterns` — tune against a week of your real scrollback

The project list is cached at `~/.cache/wezterm-projects.json`; `LEADER F`
rescans.

## Deliberate limits

No detach/reattach and no layout persistence: `LEADER f` rebuilds a project in
about a second, but restarting WezTerm loses running processes. Keep tmux on
remote boxes — WezTerm is the local multiplexer, and the prefixes differ
(`Ctrl+Space` here, whatever you use there) so they compose.
