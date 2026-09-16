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
| `wf_shells.lua`     | Where-to-work chooser: environment, then shell or project |
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
2. **Set your repo roots** in `wf_settings.lua` — `repo_roots` (inside WSL) and
   `repo_roots_windows` (on the drive). Nothing works until these are right.
3. **Neovim**: `nvim/lua/plugins/wezterm-nav.lua` adds `smart-splits.nvim` and
   publishes `IS_NVIM` so `Ctrl+hjkl` crosses the editor/terminal boundary.
   Note the leader shadows `<C-b>` inside Neovim (page-up, and blink's
   documentation scroll); use `PageUp` and `<C-f>`.
4. **Shell**: `bash/bashrc.d/wezterm-shell-integration.sh` emits OSC 133 and
   OSC 7. Without it `LEADER y`, `LEADER { }` and the git status field do not
   exist, and new splits do not inherit the current directory.
5. Open a new WezTerm and press `LEADER f`.

## Where to work: `LEADER Enter`

Consulting is not single-platform — some clients are Windows top to bottom,
others are mixed and covered through WSL. So the choice is presented rather
than assumed, in two steps:

1. **Where** — one entry per work environment: each WSL distro, plus Windows.
   `Escape` keeps whatever is already running.
2. **What** — the shells available there, then that environment's projects.
   Picking a shell opens a tab; picking a project builds its workspace.

The same picker runs **when a window opens**, so launching WezTerm can go
straight into a project rather than landing in a scratch shell first. The
common case still costs one keystroke: `Escape` at step 1 keeps the default
environment's shell — or none at all, if you just start typing in the pane
behind it.

Two steps rather than one because `LEADER f` is scoped to the domain of the
pane it was invoked from — it answers "a project where I already am". Getting
to a project *elsewhere* used to mean spawning a throwaway shell there first,
purely to move the picker's context. Naming the environment up front removes
that step.

Picking the shell that is already running is a no-op; picking a different one
opens it and drops the placeholder tab, so you never end up with a spare.

Tabs and splits made from a pane inherit its domain, so a window stays on one
platform until you ask otherwise. Edit `shells_windows` / `shells_unix` in
`wf_settings.lua` to change the shell list, or set
`startup_shell_picker = false` to go straight to the default.

Adding a WSL distribution is two entries in `wf_settings.lua`: one in
`wsl_distros`, which creates the `WSL:<distro>` domain, adds the distro to the
project scan *and* puts it in step 1; and one in `shells_windows` pointing at
that domain so step 2 has a shell to offer. `distro` must match `wsl.exe -l -v`
exactly. Ubuntu-24.04 and FedoraLinux-42 are wired up this way.

**Which environment is the default** — where a new window opens, where `@notes`
and `@scratch` live, and which environment's workspaces keep unqualified names
— is decided by `default = true` on a `wsl_distros` entry. With no entry marked,
as shipped, the role stays on the Windows side and a new window is PowerShell.
Keep the `default` flag in `shells_windows` on the shell that actually matches,
or `Escape` at startup will no-op against the wrong one.

Helper tabs follow the pane they were invoked from: `LEADER ?` and `LEADER Y`
open in the current pane's domain, so pressing them in a PowerShell pane uses
Windows `nvim` and never starts the WSL VM just to display a file.

WezTerm's own launcher (`LEADER Shift+Enter`) lists every shell plus every
registered domain — useful for confirming a domain name if a shell reports one
as unknown.

## Projects: one environment at a time

`LEADER f` lists the repositories of **the pane's own domain**, and nothing
else. In a Fedora pane you get Fedora repos; in a PowerShell pane, Windows
repos. The picker title says which (`Projects · fedora`).

That is the whole point of the domains: a project opens its entire workspace —
tabs, splits, editor, notes — in the environment it was found in, so a list
that mixed them would be offering you repositories you cannot actually work in
from where you are. A domain with no roots of its own (SSH, mux) gets a toast
rather than somebody else's list.

Two root lists, because they are two places: `~/Projects` on the C: drive has
nothing to do with `~/Projects` inside a distribution. Write the Windows ones
with forward slashes (`~/Projects`, `C:/src`) — they go to Git Bash as-is and
come back as the project's working directory, valid in both.

Each environment is cached separately in `~/.cache/wezterm-projects.json` and
scanned only when its own list is wanted, so `LEADER F` in a PowerShell pane
refreshes the Windows list without starting a stopped distro's VM. Within a
list, ordering is by mtime — what you touched most recently.

### Workspace names

Whichever environment holds the default role keeps **bare** names
(`billing-api`); every other environment is tagged with its `short`
(`billing-api@fedora`, `billing-api@ubuntu`). As shipped the role is on the
Windows side, so Windows repos are the bare ones.

The tagging is not cosmetic. A workspace name is global to the mux, so the same
name in two environments *is* one workspace: opening the second finds the first
already there, skips building it, and silently switches to it — while the
picker marks it as already open, because that marker is keyed on the same name.
`~/.dotconfigs` is scanned in every environment by design, so this would bite
immediately without it. The picker shows the tagged name, so which copy you are
opening is visible before Enter.

`windows_short` supplies the Windows tag for when a distro takes the default
role back.

### Windows specifics

- Discovery runs through `windows_bash` (Git Bash), so one `find` pipeline
  serves every environment. It is a full path on purpose: `bash.exe` from PATH
  is `C:\Windows\System32\bash.exe`, the WSL launcher, which would scan a
  distribution instead of the drive.
- Panes run `windows_shell` (pwsh), not Git Bash — Git Bash is a detail of
  discovery only.
- The notes template has a PowerShell spelling alongside the bash one, since
  `mkdir -p` and `printf` are not available to a pwsh pane.
- Without Git installed, the Windows roots simply yield nothing; WSL projects
  are unaffected. Setting `repo_roots_windows = {}` stops Windows *projects*
  being scanned or offered, but Windows stays in the `LEADER Enter` list — it
  is still somewhere shells run.

**Known gap:** `LEADER f` finds repositories, not remotes — a bare clone or a
worktree whose `.git` is a file rather than a directory is not matched.

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
