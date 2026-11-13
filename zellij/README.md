# Zellij workspace

Zellij 0.46 on native Windows, inside Windows Terminal. Windows Terminal is
only the window (font, colours, a profile that starts Zellij); Zellij owns
sessions, tabs and long-running processes; Neovim owns files, search and git.

```
session = client          acme
  tab = service             cerberus │ ORDERS_API │ ...
    ┌────────────── editor ──────────────┬──────── agent ────────┐
    │ nvim                               │ opencode ($ZJ_AGENT)  │
    ├────────────────────────────────────┴───────────────────────┤
    │ dev   zjr dev    (waits for Enter)       stacked: one open, │
    │ test  zjr test   (waits for Enter)       the others a line  │
    │ shell                                                       │
    └─────────────────────────────────────────────────────────────┘
```

| File | What it is |
| --- | --- |
| `config.kdl` | Keys (unlock-first preset), behaviour, inbox, resurrection, `zellij terminal` settings |
| `layouts/service.kdl` | One service tab, plus three swap arrangements |
| `themes/` | Everforest medium (dark and light) and Rosé Pine Dawn |
| `plugins/pilot/` | Our own plugin (Rust → wasm): Alt+hjkl across nvim and panes, the agent toggle, session switching for `zj` |
| `../powershell/Zellij.psm1` | `zj`, `zja`, `zjr` (imported by the PowerShell profile) |
| `../nvim/lua/config/zellij.lua` | nvim's half of Alt+hjkl |

## Setup

`windows/links.jsonc` links this folder to `%APPDATA%\Zellij\config`.
The plugin is built, not committed:

```pwsh
./zellij/plugins/Build-Pilot.ps1        # needs rustup; adds wasm32-wasip1 if missing
./zellij/plugins/Build-Pilot.ps1 -Test  # also runs its unit tests
```

The script also pre-grants pilot's permissions in
`%LOCALAPPDATA%\Zellij\cache\permissions.kdl`, as answering Zellij's prompt
once would. A session started in the background has no client to show that
prompt to, so without it the plugin stays inert. Running sessions keep the
old build until they restart.

| Variable | Default | Used by |
| --- | --- | --- |
| `ZJ_PROJECTS` | `~/Projects` | `zj`: the folder holding `<client>/<service>` |
| `ZJ_AGENT` | `opencode` | `zja`: the agent program (`claude`, `codex`, ...); OpenCode and Claude Code continue the folder's last conversation |

## Keys

Zellij starts **locked**: every key goes to nvim, the shell or the agent.
`Alt g` unlocks; one more key acts, and Zellij locks again.

Always available (locked too):

| Key | Does |
| --- | --- |
| `Alt h/j/k/l`, `Alt ←↓↑→` | Move between nvim windows and Zellij panes as one grid, from any nvim mode; left/right cross into the next tab at the edge |
| `Alt H/J/K/L` | Move a divider that way: nvim's window divider, or the Zellij pane divider when nvim has none that way (the right/bottom divider first) |
| `Alt 1`–`9` | Go to tab N |
| `Alt m` | Maximize (zoom) the pane and back |
| `Alt a` | To this tab's agent and back (starts one if missing) |
| `Alt u` | Next pane anywhere that needs you (agent waiting, failed tests), switching session if needed |
| `Alt \` | Previous pane |
| `Alt n` / `Alt f` | New pane / show or hide floating panes |
| `Alt =` / `Alt -` | Grow / shrink pane |

After `Alt g`:

| Key | Does |
| --- | --- |
| `f` | Projects picker (`zj`) in a float |
| `w` | Session manager (type part of a name; previews; resurrect dead sessions) |
| `i` | Inbox: every agent and long command in every session, by status |
| `g` / `y` | lazygit / yazi in a float, in the pane's folder; files they open land in the tab's nvim |
| `e` | This pane's scrollback in nvim, in place (search, motions, yank) |
| `n` | Scratch floating shell |
| `z` | Fullscreen the pane (same as `Alt m`) |
| `Space`, `[` / `]` | Next / previous arrangement: code (60/40), agent (agent wide), columns (stack on the right) |
| `,` / `.` | Move the tab left / right |
| `T` | Toggle light/dark theme |
| `d` | Detach |
| `p` `t` `r` `m` `s` `o` | Pane, tab, resize, move, scroll, session modes (the status bar lists their keys) |

Scroll mode (`Alt g s`) reads like a pager: `j`/`k`, `d`/`u`, `g`/`G` top and
bottom, `/` search then `n`/`N`, `[`/`]` between prompts, `c` copies the last
command's output (the PowerShell prompt sends OSC 133), `e` or `v` opens it all
in nvim.

Worth knowing in the other modes: `Alt g p c` renames a pane, `Alt g p v`
watches it (every finish notifies), `Alt g p u` mutes it; `Alt g o` then `Tab`
toggles the previous session.

Left to programs: `Alt p` (Claude Code's model picker), `Ctrl g` (live ripgrep
in the shell, edit-prompt in Claude Code), `Alt Enter` (newline in OpenCode),
`Alt z` (zoxide in the shell), `Alt i/o/[/]` (nvim). OpenCode's `Alt a` (start
of visual line) is the one program key the agent toggle shadows.

## Neovim in the workspace

`nvim/lua/config/zellij.lua`, `config/autoreload.lua` and flatten.nvim
(`plugins/terminal.lua`) make the tab's editor the centre of the tab.

**One editor per tab.** The nvim a service tab starts registers itself as the
tab's editor (`%LOCALAPPDATA%\nvim-data\zellij\<session>\<pane>`). Any `nvim`
started elsewhere in the tab (lazygit's `e`, yazi, `sf` / `sg` in the shell,
Zellij's click-to-open) hands its files to it, and focus moves there. Edits a
program waits for (commit and rebase messages, an agent's prompt file in
`%TEMP%` from OpenCode's editor key or Claude Code's `Ctrl g`) end with `:w`,
and focus goes back to the pane that asked. A bare `nvim` still starts its own
instance; so does the scrollback editor.

**Agent bridge** (normal mode; pastes into the agent's prompt without
submitting, then focuses it):

| Key | Sends |
| --- | --- |
| `<leader>if` | `@path` of the buffer |
| `<leader>il` | `@path line N`; in visual mode the selection as a fenced block with its line range |
| `<leader>id` | The cursor line's diagnostics (with a count, the whole buffer's) |
| `<leader>ii` | Nothing: goes to the agent (as `Alt a`) |

**Live reload.** Files the agent changes reload on their own (a watcher per
buffer, plus checks on focus and idle), with a notification. A buffer with
unsaved changes is never overwritten; nvim asks.

**Projects from nvim.** `<leader>sp` lists the same projects as `zj` (● marks
running sessions, folder preview) and opens the pick in its session and tab.

lazygit and a shell are reachable both ways: `<leader>gg` / `<C-\>` float
inside nvim and close with it; `Alt g g` / `Alt g n` float in Zellij and
outlive an nvim restart. Both send files to the same editor.

## A day

- **Morning.** Open Windows Terminal: the Zellij profile shows the session
  manager. Pick yesterday's client; after a reboot it is resurrected (see below).
- **Start on a service.** `Alt g f`, type part of the name, Enter. New
  client → new session; known client → a new tab in its session; open tab →
  focused. `●` marks clients that are running.
- **In the tab.** Edit in nvim, give the agent a task (`Alt a` jumps there and
  back), press Enter on `dev` to start the server, Enter on `test` when you
  want them. `Alt g n` for a one-off command.
- **Interruption.** Client X pings: `Alt g f` (or `Alt g w`) to its session.
  Agents left in client Y keep working; the tab bar and `Alt g i` show when
  one needs you, `Alt u` takes you there.
- **Closing the window** only detaches. Reopen and pick the session.

## Reboot and resurrection

Sessions are saved every 30 s with each pane's last screen. After a reboot,
a session is listed as EXITED; opening it (session manager, `zj`, `zellij
attach`) brings back the tabs, panes, folders and commands; each command waits
for Enter (`zellij attach -f <name>` runs them all at once). The agent pane runs `zja`, which continues the
folder's last OpenCode (or Claude Code) conversation, so Enter there picks the work up.
Running state (a dev server, an agent mid-task) is not restored.

Checked on Zellij 0.46.0, Windows 11: kill, reattach, both tabs and all panes
back.

## Watching from elsewhere

- Another terminal on this machine: `zellij watch <session>` (read-only).
- The browser or another machine: `zellij web` starts the server on
  127.0.0.1:8082; `Alt g o s` shares the current session, and `zellij web
  --create-token` (or `--create-read-only-token`) makes a login token. It
  stays off by default (`web_server false`); exposing it beyond localhost
  needs `web_server_ip`, a certificate (`web_server_cert`/`web_server_key`)
  and a token: anyone with a token can type into your shells.

## Zellij as the terminal

`zellij terminal` opens Zellij's own window (0.46) with a tray icon: the
session list and inbox from the taskbar, a badge counting what needs you, and
Windows notifications when an agent waits or a command fails. The `terminal`
block in `config.kdl` gives it the same font and Everforest colours as
Windows Terminal. Sessions are shared: attach to the same one from either.
To try it as the main terminal: `zellij setup --install-desktop-entry` (Start
menu entry, "Open Zellij here" in Explorer).

## Inbox integration

| Source | How |
| --- | --- |
| OpenCode ≥ 2.1 | Reports working / waiting for you / idle itself (OSC 7501); not done or failed |
| Claude Code ≥ 2.1.295 | Reports working / needs you / done itself (OSC 7501) |
| Shell commands | The profile's OSC 133 marks: a command over 15 s is reported when it ends, with its exit code |
| `zjr` | Reports `dev` / `test` / `build` as working, then done or error (OSC 7501) |
| Command panes | Zellij marks the exit code |

Desktop notifications are on for "needs you" and failures, off for "done".

## zjr: what runs

`zjr dev|test|build` picks by project kind; `zjr -WhatIf` prints it.

| Kind | dev | test |
| --- | --- | --- |
| .NET | Aspire AppHost: `aspire run`; else `dotnet watch` on the web project | `dotnet test` |
| Node | `<pnpm/bun/yarn/npm> run dev` (or `start`) | `run test` |
| Python | `uv run manage.py runserver` / `main.py` / `app.py` | `uv run pytest` |
| Rust, Go, Maven, Gradle | `cargo run`, `go run .`, `spring-boot:run`, `bootRun` | their test |
| Monorepo | its Aspire AppHost (project or `apphost.cs`), else `docker compose up` | – |

When it guesses wrong, put a `.zjr.json` in the folder:
`{ "dev": "npm run dev --prefix CODE", "test": "..." }`.

## Runbook

| Symptom | Fix |
| --- | --- |
| Alt+hjkl does nothing | `Build-Pilot.ps1`, then restart the session. Debug: add `debug "true"` to the `pilot` block in `config.kdl`, read `%TEMP%\zellij\zellij-log\zellij.log` (lines start `pilot:`) |
| A file opens in a new nvim instead of the tab's editor | The editor nvim must have started after this config (it registers on start); restart it. Check `%LOCALAPPDATA%\nvim-data\zellij\<session>` lists its pane |
| `nvim somefile` in a pane waits | The file is under `%TEMP%`, which counts as an agent's prompt file: `:w` in the editor releases it |
| A floating "pilot" permission prompt | Answer `y` once, or run `Build-Pilot.ps1` (writes the grant) |
| `zj` from inside does not switch | It needs pilot (`zellij action switch-session` from the CLI only moves the CLI's own connection, not your client) |
| New panes open in the wrong folder | The prompt reports the folder with OSC 7; a program that changes folder without a prompt is not tracked |
| Session stuck or zombie | `zellij ls`; `zellij kill-session <name>`; `zellij delete-session <name>` drops its resurrection data |
| Config error after an upgrade | `zellij setup --check`; compare with `zellij setup --dump-config` and `--dump-keybinds unlock-first` |
| Rollback | `windows_terminal/settings.json`: set `defaultProfile` back to PowerShell Core; the psmux setup in `tmux/` is untouched |

## Fallback

If the Windows port proves flaky: WezTerm has had native panes and workspaces
on Windows much longer, but replaces Windows Terminal instead of running
inside it. The psmux setup (`tmux/`, `tm`) still works as before.
