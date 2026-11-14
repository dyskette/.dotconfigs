# Zellij workspace

Zellij 0.46 on both machines: native Windows inside Windows Terminal, and
Linux inside Ghostty. The terminal is only the window (font, colours, a
profile that starts Zellij); Zellij owns sessions, tabs and long-running
processes; Neovim owns files, search and git.

Keys, layout and workflow are the same on both. What differs is the shell and
the commands the config names — pwsh with `powershell/Zellij.psm1` on Windows,
bash with `zellij/bin/*` on Linux — so `config.kdl` and `layouts/service.kdl`
exist twice (KDL has no includes and Zellij expands no variables in them).
Everything else is one file: the keys, the themes, the lobby layout and the
plugin.

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
| `config.kdl` | Windows: keys (unlock-first preset), behaviour, inbox, resurrection, `zellij terminal` settings |
| `layouts/service.kdl` | Windows: one service tab, plus three swap arrangements |
| `linux/config.kdl`, `linux/layouts/service.kdl` | The Linux twins of those two: bash, `zja`, `zjr`, `zj-hub-projects`. The rest is meant to stay word for word the same |
| `layouts/lobby.kdl` | The hub alone, full screen: what the terminal opens on |
| `themes/` | Everforest medium (dark and light) and Rosé Pine Dawn |
| `plugins/pilot/` | Our own plugin (Rust → wasm). Headless in every session: Alt+hjkl across nvim and panes, the agent toggle, keeping sessions from being deleted. As a pane: the session hub (`src/hub`) |
| `plugins/Build-Pilot.ps1`, `plugins/build-pilot.sh` | Build it and pre-grant its permissions, on Windows and on Linux |
| `plugins/tests/` | Tools for end-to-end checks: type keys into, and read the screen of, a test window without focus |
| `bin/` | Linux: `zj`, `zja`, `zjr`, `zj-hub-projects` and the `zj-lib.sh` they share |
| `../powershell/Zellij.psm1` | Windows: the same commands as functions (imported by the PowerShell profile) |
| `../nvim/lua/config/zellij.lua` | nvim's half of Alt+hjkl, the agent bridge, `<leader>sp` |

## Setup

**Windows.** `windows/links.jsonc` links this folder to
`%APPDATA%\Zellij\config`. The plugin is built, not committed:

```pwsh
./zellij/plugins/Build-Pilot.ps1        # needs rustup; adds wasm32-wasip1 if missing
./zellij/plugins/Build-Pilot.ps1 -Test  # also runs its unit tests
```

**Linux.** `linux/tasks/dotfiles.yml` fills `~/.config/zellij` with links —
`config.kdl` and `layouts/service.kdl` from `zellij/linux/`, `layouts/lobby.kdl`,
`themes/` and `plugins/` from here — links `bin/*` into `~/.local/bin`, and
builds the plugin. By hand:

```bash
./zellij/plugins/build-pilot.sh         # needs rustup; adds wasm32-wasip1 if missing
./zellij/plugins/build-pilot.sh --test  # also runs its unit tests
./linux/tests/zj-lib.test.sh            # the bash half of zj, zjr and the hub list
```

`--test` builds for the host, which needs a C toolchain and OpenSSL headers
(a `toolbox` on Fedora Silverblue); the wasm build itself needs neither.

Both scripts also pre-grant pilot's permissions in Zellij's cache
(`%LOCALAPPDATA%\Zellij\cache\permissions.kdl`,
`~/.cache/zellij/permissions.kdl`), as answering Zellij's prompt once would. A
session started in the background has no client to show that prompt to, so
without it the plugin stays inert. Running sessions keep the old build until
they restart.

| Variable | Default | Used by |
| --- | --- | --- |
| `ZJ_PROJECTS` | `~/Projects`, or whichever of `~/Projects` and `~/Proyectos` holds folders on Linux | The hub and `zj`: the folder holding `<client>/<service>` |
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
| `Alt s` | The session hub: sessions, saved sessions and projects (see "The hub") |
| `Alt a` | To this tab's agent and back (starts one if missing) |
| `Alt u` | Next pane anywhere that needs you (agent waiting, failed tests), switching session if needed |
| `Alt \` | Previous pane |
| `Alt n` / `Alt f` | New pane / show or hide floating panes |
| `Alt =` / `Alt -` | Grow / shrink pane |

After `Alt g`:

| Key | Does |
| --- | --- |
| `w` / `f` | The session hub (as `Alt s`) |
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

## The hub

One place answers "where do I want to be?": running sessions, saved sessions
and projects in one list, with a preview. It is the same view everywhere, in
two sizes:

- **Full screen when you are in no session**: the terminal opens on it (`zj`
  without arguments, in a throwaway `lobby-…` session; Windows Terminal's
  default profile runs it, and on Linux it is what you type, or a Ghostty
  `command = zj`). Detaching from a session brings it back; `Esc` then `q`
  there leaves Zellij for a plain shell.
- **A popup when you are in one**: `Alt s` (also `Alt g w`, `Alt g f`, `zj`
  without arguments, and `<leader>sp` in nvim).

The bottom line always says what Enter will do on the selected row: `attach`,
`go to tab`, `resurrect`, `new tab in <session>`, `new session`, `create`.
The current session is listed dimmed ("you are here"); the cursor starts on
the previous one, so `Alt s` `Enter` toggles between the last two.

It opens in **insert** mode: type to filter (the list is then ranked by match
quality across sessions, tabs and projects, and a last row offers to create a
session named after what you typed).

| Insert | |
| --- | --- |
| type | Filter |
| `Ctrl-n` `Ctrl-p` / `Ctrl-j` `Ctrl-k` | Move |
| `Ctrl-w` / `Ctrl-u` | Delete a word / clear |
| `Enter` | Open |
| `Esc` | Normal mode; the filter stays |

| Normal | |
| --- | --- |
| `j` `k`, `gg` `G`, `Ctrl-d` `Ctrl-u` | Move |
| `l` | Unfold a session, then step into its tabs; opens only a leaf (a tab, a saved session, a project) |
| `h` | To the tab's session, then fold it (`zo` / `zc` fold without moving) |
| `Enter` | Always opens |
| `o` | New: a folder to open (any path, `~` included), or a name for an empty session |
| `r` | Rename the session or tab |
| `dd` | One step down: a running session is stopped and stays saved; a saved one is deleted; a tab is closed |
| `/` `i` | Back to the filter |
| `p` / `?` | Preview on or off / all keys |
| `q` `Esc` | Close |

`dd` asks first only when it cannot be undone (deleting a saved session,
always by name), when an agent is working or something needs you there, or
when it is the session you are in (you are moved to the previous one). A
second `dd` on a session just stopped therefore asks.

Projects follow the same rule as `zj <folder>`: the first folder under the
projects root is the client (the session), the last one the service (the
tab). Saved sessions untouched for 14 days sink to the bottom of their
section; nothing is ever deleted on its own, except lobbies nobody is in.

The inbox (`Alt g i`, `Alt u`) stays separate: it answers "what needs me?".
The hub only marks sessions and tabs with `⚑N`.

## Neovim in the workspace

`nvim/lua/config/zellij.lua`, `config/autoreload.lua` and flatten.nvim
(`plugins/terminal.lua`) make the tab's editor the centre of the tab.

**One editor per tab.** The nvim a service tab starts registers itself as the
tab's editor, in nvim's own state folder
(`%LOCALAPPDATA%\nvim-data\zellij\<session>\<pane>`,
`~/.local/state/nvim/zellij/<session>/<pane>`). Any `nvim` started elsewhere in
the tab (lazygit's `e`, yazi, `sf` / `sg` in the shell, Zellij's
click-to-open) hands its files to it, and focus moves there. Edits a program
waits for (commit and rebase messages, an agent's prompt file in the temp
folder from OpenCode's editor key or Claude Code's `Ctrl g`) end with `:w`,
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

**The hub from nvim.** `<leader>sp` opens the session hub, as `Alt s` does.

lazygit and a shell are reachable both ways: `<leader>gg` / `<C-\>` float
inside nvim and close with it; `Alt g g` / `Alt g n` float in Zellij and
outlive an nvim restart. Both send files to the same editor.

## A day

- **Morning.** Open the terminal (`zj`): the hub, on the session you used last.
  Enter; after a reboot that resurrects it (see below).
- **Start on a service.** `Alt s`, type part of the name, Enter. The hint
  says what will happen: a new session for a new client, a new tab in a
  known client's session, or just a jump to a tab that is open.
- **In the tab.** Edit in nvim, give the agent a task (`Alt a` jumps there and
  back), press Enter on `dev` to start the server, Enter on `test` when you
  want them. `Alt g n` for a one-off command.
- **Interruption.** Client X pings: `Alt s`, type, Enter; `Alt s` `Enter`
  comes back. Agents left in client Y keep working; the tab bar and `Alt g i`
  show when one needs you, `Alt u` takes you there.
- **Closing the window** only detaches; so does `Alt g d`, which returns to
  the hub.

## Reboot and resurrection

Sessions are saved every 30 s with each pane's last screen. After a reboot,
a session is listed as saved (`○` in the hub); opening it (the hub, `zj`, `zellij
attach`) brings back the tabs, panes, folders and commands; each command waits
for Enter (`zellij attach -f <name>` runs them all at once). The agent pane runs `zja`, which continues the
folder's last OpenCode (or Claude Code) conversation, so Enter there picks the work up.
Running state (a dev server, an agent mid-task) is not restored.

Checked on Zellij 0.46.0, Windows 11 and Fedora Silverblue 45: kill, reattach,
both tabs and all panes back.

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
desktop notifications when an agent waits or a command fails. The `terminal`
block in both configs gives it the same font and Everforest colours as Windows
Terminal and Ghostty. Sessions are shared: attach to the same one from either.
To try it as the main terminal: `zellij setup --install-desktop-entry` (a
Start menu entry and "Open Zellij here" in Explorer; a `.desktop` file under
`~/.local/share/applications` on Linux).

## Inbox integration

| Source | How |
| --- | --- |
| OpenCode ≥ 2.1 | Reports working / waiting for you / idle itself (OSC 7501); not done or failed |
| Claude Code ≥ 2.1.295 | Reports working / needs you / done itself (OSC 7501) |
| Shell commands | The prompt's OSC 133 marks (`powershell/Microsoft.PowerShell_profile.ps1`, `bash/bashrc.d/prompt.sh`): a command over 15 s is reported when it ends, with its exit code |
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
| Alt+hjkl does nothing | `Build-Pilot.ps1` / `build-pilot.sh`, then restart the session. Debug: add `debug "true"` to the `pilot` block in the config, read Zellij's log (`%TEMP%\zellij\zellij-log\zellij.log`, `/tmp/zellij-<uid>/zellij-log/zellij.log`); lines start `pilot:` |
| A file opens in a new nvim instead of the tab's editor | The editor nvim must have started after this config (it registers on start); restart it. Check that nvim's state folder (`%LOCALAPPDATA%\nvim-data\zellij\<session>`, `~/.local/state/nvim/zellij/<session>`) lists its pane |
| `nvim somefile` in a pane waits | The file is under the temp folder, which counts as an agent's prompt file: `:w` in the editor releases it |
| A session vanished after switching away (not even listed as EXITED) | Zellij 0.46 deletes a session nobody pressed Enter in when Zellij's own session manager (the inbox, the session card) leaves it; the hub never does. pilot marks every session as used when it starts or is resurrected: an Enter key event without bytes in a pane running a plain shell, or, in a resurrected session, the Enter that starts a held bare shell. A session with no shell pane at all (only nvim, an agent, a dev server) still needs one Enter from you before it is safe to leave |
| A session named `.something` cannot be found | Zellij cannot list or reach names starting or ending with a dot; `zj` strips them (`~/.dotconfigs` → `dotconfigs`) |
| New tabs fail with `0x80070002` launching `pwsh.exe`; Start-menu apps miss tools | Explorer drops the whole user PATH when system + user PATH exceed about 4,095 characters, as soon as anything broadcasts an environment change. Shorten the user PATH (duplicates, folders whose programs are found earlier), then close every Windows Terminal window and reopen it |
| The hub opens empty, or with a permission prompt | Run `Build-Pilot.ps1` (it grants the plugin's permissions) and restart the session; both views of the plugin must ask for the same set, `PERMISSIONS` in `src/main.rs` |
| The hub lists no projects | It runs `projects_command` (the config) in the background and caches the result: check that `Get-ZjHubProject` / `zj-hub-projects` prints `root=…` and the folders. On Linux the root is `$ZJ_PROJECTS`, or whichever of `~/Projects` and `~/Proyectos` holds folders |
| The terminal opens a shell, not the hub | The loop ended: Zellij exited within two seconds (a config error: `zellij setup --check`), or the hub was quit with `q`. `zj` starts it again |
| `zj`, `zja` or `zjr` not found, or the old fzf picker runs (Linux) | `~/.local/bin` must be on PATH and hold the links to `zellij/bin/*` (`ansible-playbook` with `--tags dotfiles`). The old `zj` fzf function is gone from `bash/bashrc.d/fzf.sh`; open a new shell |
| A service tab opens named "service", in the wrong folder | `zj` and the hub replace the tab line of `layouts/service.kdl` (`ui name="service" focus=true`) with the tab's name and folder, and take the first match in the file: no comment may repeat it |
| A floating "pilot" permission prompt | Answer `y` once, or run `Build-Pilot.ps1` (writes the grant) |
| `zj` from inside does not switch | It needs pilot (`zellij action switch-session` from the CLI only moves the CLI's own connection, not your client) |
| New panes open in the wrong folder | The prompt reports the folder with OSC 7; a program that changes folder without a prompt is not tracked |
| Session stuck or zombie | `zellij ls`; `zellij kill-session <name>`; `zellij delete-session <name>` drops its resurrection data |
| Config error after an upgrade | `zellij setup --check`; compare with `zellij setup --dump-config` and `--dump-keybinds unlock-first` |
| Rollback | `windows_terminal/settings.json`: set `defaultProfile` back to PowerShell Core; on Linux just stop typing `zj`. The psmux setup in `tmux/` is untouched on both |

## Fallback

If the Windows port proves flaky: WezTerm has had native panes and workspaces
on Windows much longer, but replaces Windows Terminal instead of running
inside it. The psmux setup (`tmux/`, `tm`) still works as before.
