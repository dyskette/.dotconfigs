# Zellij workspace

Zellij 0.46 on both machines: native Windows inside Windows Terminal, and
Linux inside Ghostty. The terminal is only the window (font, colours, a
profile that starts Zellij); Zellij owns sessions, tabs and long-running
processes; Neovim owns files, search and git.

Keys, layout and workflow are the same on both. What differs is the shell and
the commands the config names — pwsh with `powershell/Zellij.psm1` on Windows,
bash with `zellij/bin/*` on Linux — so `config.kdl` exists twice (KDL has no
includes and Zellij expands no variables in them). Everything else is one
file: the keys, the themes, the lobby layout and the plugin.

**One session per repo, one tab per activity.** Why it is shaped this way is
in `decisions/0001-workspace-model.md`.

```
session = repo            orders-api            (Alt s switches between them)
  tab = activity            editor │ agent │ lazygit
    ┌──────────────── one activity, full screen ───────────────┐
    │ nvim                                                     │
    │                                                          │
    │   Alt e/a/g go to one, starting it if the session has    │
    │   none; Alt h/l cross between them at the edge           │
    │                                                          │
    │   Alt t / Alt n: floats, for the ephemeral shells        │
    └──────────────────────────────────────────────────────────┘
```

| File | What it is |
| --- | --- |
| `config.kdl` | Windows: keys (no preset: `clear-defaults`, everything in the locked block), behaviour, inbox, resurrection, `zellij terminal` settings |
| `linux/config.kdl` | The Linux twin: bash, `zja`, `zj-hub-projects`. The rest is meant to stay word for word the same |
| `decisions/` | Why the workspace is shaped the way it is |
| `layouts/lobby.kdl` | The hub alone, full screen: what the terminal opens on |
| `themes/` | Everforest medium (dark and light) and Rosé Pine Dawn |
| `plugins/pilot/` | Our own plugin (Rust → wasm). Headless in every session: Alt+hjkl across nvim and panes, the activity tabs (`Alt e/a/g`), keeping sessions from being deleted. As a pane: the session hub (`src/hub`) |
| `plugins/Build-Pilot.ps1`, `plugins/build-pilot.sh` | Build it and pre-grant its permissions, on Windows and on Linux |
| `plugins/tests/` | Tools for end-to-end checks: type keys into, and read the screen of, a test window without focus |
| `bin/` | Linux: `zj`, `zja`, `zjr`, `zj-hub-projects` and the `zj-lib.sh` they share |
| `../nvim/lua/config/zellij.lua` | nvim's half of Alt+hjkl, the agent bridge, `<leader>sp` |
| `../powershell/Zellij.psm1` | Windows: the same commands as functions (imported by the PowerShell profile) |

## Setup

**Windows.** `windows/links.jsonc` links this folder to
`%APPDATA%\Zellij\config`. The plugin is built, not committed:

```pwsh
./zellij/plugins/Build-Pilot.ps1        # needs rustup; adds wasm32-wasip1 if missing
./zellij/plugins/Build-Pilot.ps1 -Test  # also runs its unit tests
```

**Linux.** `linux/tasks/dotfiles.yml` fills `~/.config/zellij` with links —
`config.kdl` from `zellij/linux/`, `layouts/lobby.kdl`,
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

No prefix and no modes, bar one. Zellij stays **locked**, so every key that
is not bound here goes to nvim, the shell or the agent, and the bindings are
all `Alt` keys. The rule: **`Alt` moves, `Alt+Shift` nudges a divider, and a
letter goes to the thing it names.**

`Ctrl a` is left alone, for readline's beginning-of-line.

| Key | Does |
| --- | --- |
| `Alt h/j/k/l`, `Alt ←↓↑→` | Move between nvim windows and Zellij panes as one grid, from any nvim mode; left/right cross into the next tab at the edge, which is how you get from the editor to the agent and back |
| `Alt H/J/K/L` | Move a divider that way: nvim's window divider, or the Zellij pane divider when nvim has none that way (the right/bottom divider first) |
| `Alt r` | Sticky resize: `hjkl` repeat, `Esc` leaves. The only mode |
| `Alt e` / `Alt a` / `Alt g` | The editor, agent or lazygit tab; pressing it while already there goes back where you came from, and a session without that tab yet gets one |
| `Alt t` | Raise the tab's floating layer and put it away; focus is kept on both sides, and a tab with no float yet gets a shell |
| `Alt n` | New scratch floating shell |
| `Alt s` | The session hub (see "The hub"), the way between repos |
| `Alt c` | Inbox: every agent and long command in every session, by status |
| `Alt u` | Next pane anywhere that needs you (agent waiting, failed tests), switching session if needed |
| `Alt m` | Maximize (zoom) the pane and back |
| `Alt \` | Previous pane |
| `Alt v` | This pane's scrollback in nvim, with motions, text objects and yank |
| `Alt T` | Toggle light/dark theme |
| `Alt d` / `Alt q` | Detach / quit (quit asks, with detach preselected) |

There is **no scroll mode and no search mode**: `Alt v` hands the whole
scrollback to nvim, which beats a pager for someone who lives in one, and it
keeps the promise that there are no modes. The mouse still scrolls.

Left to programs: `Alt p` (Claude Code's model picker), `Ctrl g` (live ripgrep
in the shell, edit-prompt in Claude Code), `Alt Enter` (newline in OpenCode),
`Alt z` (zoxide in the shell), `Alt i/o/[/]` and `Alt f` (nvim, fzf's preview
paging). Without a prefix there is no way to send a key Zellij has taken, so
`Alt e`, `Alt a` and `Alt g` were picked to miss what the agents use.

## The hub

One place answers "where do I want to be?": running sessions, saved sessions
and projects in one list, with a preview. It is the same view everywhere, in
two sizes:

- **Full screen when you are in no session**: the terminal opens on it (`zj`
  without arguments, in a throwaway `lobby-…` session; Windows Terminal's
  default profile runs it, and on Linux it is what you type, or a Ghostty
  `command = zj`). Detaching from a session brings it back; `Esc` then `q`
  there leaves Zellij for a plain shell.
- **A popup when you are in one**: `Alt s` (also `zj` without arguments, and
  `<leader>sp` in nvim).

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

Projects follow the same rule as `zj <folder>`: a session named after the
folder itself, wherever it sits. A repo appears once — under Running or
Saved when it has a session, under Projects when it has never been opened —
so the three states are one section each. Saved sessions untouched for 14
days sink to the bottom of their section; nothing is ever deleted on its
own, except lobbies nobody is in.

`o` takes a folder to open, or a name for an empty session. `u` takes a
folder to open as an **umbrella**: rooted above several repos and starting
on an agent rather than an editor, for the questions that span them. Both
accept a typed path, so a repo outside the projects root needs no detour
through a shell (cloning still does).

The inbox (`Alt c`, `Alt u`) stays separate: it answers "what needs me?".
The hub only marks sessions and tabs with `⚑N`.

## Neovim in the workspace

`nvim/lua/config/zellij.lua`, `config/autoreload.lua` and flatten.nvim
(`plugins/terminal.lua`) make the session's editor the centre of the session.

**One editor per session.** The nvim in the editor tab registers itself, in
nvim's own state folder
(`%LOCALAPPDATA%\nvim-data\zellij\<session>\<pane>`,
`~/.local/state/nvim/zellij/<session>/<pane>`). Any `nvim` started anywhere in
the session (lazygit's `e`, `sf` / `sg` in the shell, Zellij's
click-to-open) hands its files to it, and focus moves there. Per session and
not per tab because lazygit has a tab of its own now, so its `e` has to reach
across tabs — which also means finding the editor costs no `list-panes` call,
and so no process, on the path of opening a file. Edits a program
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
inside nvim and close with it; `Alt g` is lazygit's own tab and `Alt n` a
Zellij float, both outliving an nvim restart. All of them send files to the
same editor.

The file manager lives inside nvim only: `<leader>e` opens yazi at the
current file, with the diagnostics nvim pushes into it, and opens what you
pick in process. There is no Zellij-level yazi, because from the editor tab
`<leader>e` is already there and from a float shell `y` is.

## A day

- **Morning.** Open the terminal (`zj`): the hub, on the session you used last.
  Enter; after a reboot that resurrects it (see below).
- **Start on a repo.** `Alt s`, type part of the name, Enter. The hint says
  what will happen: attach to it, resurrect it, or create it.
- **In the session.** Edit in nvim. `Alt a` starts the agent in its own tab
  and goes there; `Alt e` comes back. `Alt g` is lazygit. `Alt n` floats a
  shell for a one-off command, `zjr test` in it when you want the tests.
- **Interruption.** Another repo pings: `Alt s`, type, Enter; `Alt s` `Enter`
  comes back. Agents left behind keep working; the tab bar and `Alt c` show
  when one needs you, `Alt u` takes you there.
- **A question spanning repos.** `Alt s`, `u`, the parent folder: an umbrella
  session with an agent that can read across all of them.
- **Closing the window** only detaches; so does `Alt d`, which returns to
  the hub.

## Reboot and resurrection

Sessions are saved every 30 s with each pane's last screen. After a reboot,
a session is listed as saved (`○` in the hub); opening it (the hub, `zj`, `zellij
attach`) brings back the tabs, panes, folders and commands; each command waits
for Enter (`zellij attach -f <name>` runs them all at once). An agent tab runs `zja`, which continues the
folder's last OpenCode (or Claude Code) conversation, so Enter there picks the work up.
Running state (a dev server, an agent mid-task) is not restored.

Checked on Zellij 0.46.0, Windows 11 and Fedora Silverblue 45: kill, reattach,
both tabs and all panes back.

## Watching from elsewhere

- Another terminal on this machine: `zellij watch <session>` (read-only).
- The browser or another machine: `zellij web` starts the server on
  127.0.0.1:8082; `zellij action share-session` shares the current one, and `zellij web
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

`zjr dev|test|build` picks by project kind; `zjr -WhatIf` prints it. Run it
by hand, usually from a scratch float (`Alt n`): no layout pane runs it, as
the long-running services live outside the terminal. The pane still exits
with the command's code, so the inbox reports it as done or failed.

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
| A session opens in the wrong folder | `zj` and the hub write the folder into the layout they create the session with (`zj_session_layout`, `New-ZjSessionLayout`, `target::session_layout`): Zellij ignores `--cwd` for a session started in the background |
| `Alt e` / `Alt a` / `Alt g` opens a second tab instead of going to the one there | The tab is matched by name (`editor`, `agent`, `lazygit`); renaming it loses pilot's handle on it |
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
