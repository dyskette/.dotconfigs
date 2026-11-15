//! pilot: a headless Zellij plugin that makes the editor and the agent feel
//! like one workspace.
//!
//! It is loaded in the background (`load_plugins` in config.kdl) and driven by
//! keybindings through `MessagePlugin "pilot" { name "<command>"; ... }`:
//!
//! - `nav` (payload `left|right|up|down`): if the focused pane runs Neovim,
//!   the Alt+h/j/k/l key is written to it, so Neovim moves between its own
//!   windows (nvim/lua/config/zellij.lua). Neovim calls back into Zellij with
//!   `zellij action move-focus-or-tab` when it is already at its edge. Any
//!   other pane moves Zellij's focus directly, crossing into the next tab at
//!   the left and right screen edges.
//! - `nav-pane`: the same move without the Neovim check, sent by Neovim when it
//!   is at its own edge (`zellij action move-focus` from a pane has no client
//!   to move).
//! - `activity` (payload `editor`, `agent` or `lazygit`): goes to the tab
//!   holding that activity, back where it came from when already there, or
//!   starts it in a new tab named for it, in the focused pane's directory.
//!   The commands come from the `editor_command`, `agent_command` and
//!   `git_command` settings. One activity per tab, full screen, started on
//!   demand: see zellij/decisions/0001-workspace-model.md.
//! - `resize` (payload `left|right|up|down`): Alt+Shift+h/j/k/l. Neovim gets
//!   the key and moves its window divider; other panes move a Zellij pane
//!   divider. `resize-pane` skips the Neovim check (Neovim's fallback when
//!   it has no divider in that direction).
//! - `focus` (payload: a terminal pane id): focuses that pane for the user.
//!   `zellij action focus-pane-id` from a pane exits 0 but leaves the user's
//!   client where it was, as `switch-session` does; Neovim uses this to bring
//!   its pane forward when a file arrives and to give focus back afterwards.
//! - `switch` (payload: a KDL layout or `-`; args `session`, `tab`, `cwd`,
//!   `pane`): moves the user's client to another session, used by `zj`
//!   (powershell/Zellij.psm1). See `switch_session` for why it lives here.
//!
//! Why a plugin instead of plain keybindings: a keybinding cannot ask which
//! program a pane runs, and the plugin API answers that synchronously
//! (`get_pane_running_command`), so there is no title matching and no lag.

mod hub;
mod pending;
mod shell;

use std::collections::BTreeMap;
use std::path::PathBuf;

use zellij_tile::prelude::*;

/// Program names (lower case, without `.exe`) that receive the navigation key
/// instead of Zellij.
const EDITORS: &[&str] = &["nvim", "vim", "vi"];

/// Everything either view needs. Both ask for the same set: Zellij caches
/// the last set a plugin file was granted, so a view asking for more than
/// the other would be prompted again each time the other had run.
/// Build-Pilot.ps1 grants this list; keep the two in step.
pub const PERMISSIONS: &[PermissionType] = &[
    PermissionType::ReadApplicationState,
    PermissionType::ChangeApplicationState,
    PermissionType::WriteToStdin,
    PermissionType::RunCommands,
    PermissionType::OpenTerminalsOrPlugins,
    PermissionType::RunActionsAsUser,
    // The hub's previews of other sessions.
    PermissionType::ReadPaneContents,
];

/// The plugin alias of the hub popup (config.kdl).
const HUB_ALIAS: &str = "hub";

/// Lobbies are swept at most this often: every pane update would otherwise
/// ask Zellij for the session list.
const LOBBY_SWEEP_EVERY_SECS: u64 = 5;

/// A lobby without a client is only swept once it is this old.
const LOBBY_MIN_AGE_SECS: u64 = 10;

fn unix_now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// Name given to agent panes, which is how Neovim's agent bridge finds one
/// (nvim/lua/config/zellij.lua).
const AGENT_PANE: &str = "agent";

/// One thing to be doing, each in a tab of its own, full screen. A tab is
/// named for its activity, and that name is how it is found again: `Alt e`,
/// `Alt a` and `Alt g` go to one, or start it in a new tab when the session
/// has none (zellij/decisions/0001-workspace-model.md).
#[derive(Clone, Copy, PartialEq, Debug)]
enum Activity {
    Editor,
    Agent,
    Git,
}

impl Activity {
    /// The tab name, which doubles as the key the pipe takes.
    fn name(self) -> &'static str {
        match self {
            Activity::Editor => "editor",
            Activity::Agent => "agent",
            Activity::Git => "lazygit",
        }
    }

    fn parse(name: &str) -> Option<Self> {
        match name.trim() {
            "editor" => Some(Activity::Editor),
            "agent" => Some(Activity::Agent),
            "lazygit" | "git" => Some(Activity::Git),
            _ => None,
        }
    }
}

#[derive(Default)]
struct Pilot {
    /// Panes per tab position, kept current by `PaneUpdate`.
    panes: PaneManifest,
    /// Tabs by position, kept current by `TabUpdate`: their viewport size
    /// tells which pane edges are dividers.
    tabs: Vec<TabInfo>,
    /// The agent launcher, split on whitespace (`agent_command` setting).
    agent_command: Vec<String>,
    /// The editor and lazygit launchers (`editor_command`, `git_command`),
    /// so that a tab can be started for either.
    editor_command: Vec<String>,
    git_command: Vec<String>,
    /// The tab that had focus before the current one, so that going to an
    /// activity you are already on takes you back where you came from.
    last_tab: Option<usize>,
    /// Set once the user granted the permissions; commands before that would
    /// fail silently.
    ready: bool,
    /// `debug "true"`: log each decision to the Zellij log
    /// (%TEMP%\zellij\zellij-log\zellij.log on Windows).
    debug: bool,
    /// Progress of marking this session as used; see `keep_session`.
    keep: Keep,
    /// The session this instance runs in, from `ModeUpdate`.
    session: Option<String>,
    /// When lobbies were last swept (unix seconds); see `sweep_lobbies`.
    swept_at: u64,
    /// Set when this instance is the session hub (`view "hub"`) instead of
    /// the headless pilot: it then only draws and drives the hub.
    hub: Option<shell::HubShell>,
}

/// Zellij 0.46 treats a session nobody pressed Enter in as disposable: when
/// the session manager (Alt g w, the inbox, the session card) switches away
/// from it, the session is killed and its resurrection data deleted
/// (`SwitchSessionAndCloseCurrent`). A service tab starts nvim and the agent
/// by itself, so reading code and switching away lost the whole session, and
/// so did leaving a session resurrected after a reboot.
///
/// The only thing that marks a session as used is an unmodified Enter key
/// from the user's client in a terminal pane. pilot sends one on the user's
/// behalf: an Enter key event with no bytes, in a pane running a plain shell
/// (any session, service tab or not; shells do not use the kitty keyboard
/// protocol, so no byte is written), then gives focus back.
#[derive(Default, Debug, PartialEq)]
enum Keep {
    /// Waiting for a client and a tab with a shell pane.
    #[default]
    Waiting,
    /// Asked Zellij whether a command was submitted already.
    Checking,
    /// Sent the Enter; focus goes back to this pane once it is done.
    Marking(PaneId),
    /// The session counts as used.
    Done,
}

/// Programs (lower case, without `.exe`) a pane may run to take the Enter.
const SHELLS: &[&str] = &["pwsh", "powershell", "cmd", "bash", "sh", "zsh"];

/// Context tag of the action pilot runs, to recognise its completion.
const KEEP_CONTEXT: &str = "pilot-keep-session";

impl Pilot {
    fn log(&self, message: impl FnOnce() -> String) {
        if self.debug {
            eprintln!("pilot: {}", message());
        }
    }
}

register_plugin!(Pilot);

impl ZellijPlugin for Pilot {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        if configuration.get("view").is_some_and(|v| v == "hub") {
            self.hub = Some(shell::HubShell::load(&configuration));
            return;
        }
        let command = |key: &str, fallback: &str| -> Vec<String> {
            configuration
                .get(key)
                .map(String::as_str)
                .unwrap_or(fallback)
                .split_whitespace()
                .map(str::to_owned)
                .collect()
        };
        self.agent_command = command("agent_command", "");
        self.editor_command = command("editor_command", "nvim");
        self.git_command = command("git_command", "lazygit");
        self.debug = configuration.get("debug").is_some_and(|v| v == "true");

        request_permission(PERMISSIONS);

        subscribe(&[
            EventType::PaneUpdate,
            EventType::TabUpdate,
            EventType::ModeUpdate,
            EventType::PermissionRequestResult,
            EventType::SessionSuggestions,
            EventType::TerminalCommandSubmitted,
            EventType::ActionComplete,
        ]);
        // Headless: never take focus or space.
        set_selectable(false);
    }

    fn update(&mut self, event: Event) -> bool {
        if let Some(hub) = &mut self.hub {
            return hub.update(event);
        }
        match event {
            Event::PaneUpdate(manifest) => {
                self.panes = manifest;
                self.keep_session();
                self.run_pending();
                self.sweep_lobbies();
            }
            Event::ModeUpdate(mode) => {
                self.session = mode.session_name;
                self.run_pending();
                self.sweep_lobbies();
            }
            Event::TabUpdate(tabs) => {
                // Remember where focus came from, so that Alt a pressed on
                // the agent goes back rather than nowhere.
                let before = self.tabs.iter().find(|t| t.active).map(|t| t.position);
                let after = tabs.iter().find(|t| t.active).map(|t| t.position);
                if before.is_some() && before != after {
                    self.last_tab = before;
                }
                self.tabs = tabs;
            }
            Event::SessionSuggestions(suggestions) if self.keep == Keep::Checking => {
                if suggestions.command_submitted {
                    self.keep = Keep::Done;
                } else {
                    self.mark_session_used();
                }
            }
            Event::TerminalCommandSubmitted => {
                if let Keep::Marking(pane) = self.keep {
                    focus_pane_with_id(pane, false, false);
                }
                self.keep = Keep::Done;
            }
            Event::ActionComplete(_, _, context) if context.contains_key(KEEP_CONTEXT) => {
                if let Keep::Marking(pane) = self.keep {
                    focus_pane_with_id(pane, false, false);
                    self.keep = Keep::Done;
                }
            }
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                self.ready = true;
                self.keep_session();
            }
            Event::PermissionRequestResult(PermissionStatus::Denied) => {
                eprintln!("pilot: permissions denied; navigation and agent keys are disabled");
            }
            _ => {}
        }
        false
    }

    fn render(&mut self, rows: usize, cols: usize) {
        if let Some(hub) = &mut self.hub {
            hub.render(rows, cols);
        }
    }

    fn pipe(&mut self, message: PipeMessage) -> bool {
        if self.hub.is_some() {
            return false; // pipes are pilot's commands
        }
        self.log(|| format!("pipe {} {:?} (ready: {})", message.name, message.payload, self.ready));
        // A CLI pipe (`zellij pipe`) ends with a message without payload;
        // every command carries one, so that one is skipped instead of
        // running the command twice.
        let (true, Some(payload)) = (self.ready, message.payload.as_deref()) else {
            return false;
        };
        match message.name.as_str() {
            "nav" | "nav-pane" => match parse_direction(payload) {
                Some(direction) => self.navigate(direction, message.name == "nav"),
                None => eprintln!("pilot: nav expects left, right, up or down, not '{payload}'"),
            },
            "activity" => match Activity::parse(payload) {
                Some(kind) => self.activity(kind),
                None => eprintln!("pilot: activity expects editor, agent or lazygit, not '{payload}'"),
            },
            "resize" | "resize-pane" => match parse_direction(payload) {
                Some(direction) => self.resize(direction, message.name == "resize"),
                None => eprintln!("pilot: resize expects left, right, up or down, not '{payload}'"),
            },
            "focus" => match payload.trim().parse::<u32>() {
                Ok(id) => focus_terminal_pane(id, false, false),
                Err(_) => eprintln!("pilot: focus expects a terminal pane id, not '{payload}'"),
            },
            "switch" => self.switch_session(&message.args, payload),
            // `zj` without arguments and nvim's <leader>sp: the hub, as Alt s.
            "hub" => {
                open_plugin_pane_floating(HUB_ALIAS, BTreeMap::new(), None, BTreeMap::new());
            }
            // Pipes without a plugin target reach every plugin; the built-in
            // ones broadcast their own (session_panel_size, ...).
            other => self.log(|| format!("ignoring pipe '{other}'")),
        }
        false
    }
}

impl Pilot {
    /// Hand the key to an editor pane, or move Zellij's focus.
    fn navigate(&self, direction: Direction, editor_first: bool) {
        let focused = get_focused_pane_info();
        self.log(|| format!("nav {direction:?}, focused {focused:?}"));
        let Ok((_, pane)) = focused else {
            return;
        };

        let editor = editor_first && is_editor(pane);
        self.log(|| format!("{pane:?} runs an editor: {editor}"));
        if editor {
            // Alt+<key> in legacy encoding: ESC followed by the key. Neovim
            // reads it as <M-key> (config/zellij.lua maps those).
            write_to_pane_id(vec![0x1b, key_for(direction)], pane);
            return;
        }

        match direction {
            Direction::Left | Direction::Right => move_focus_or_tab(direction),
            Direction::Up | Direction::Down => move_focus(direction),
        }
    }

    /// Move a divider in a direction: the focused pane's right (or bottom)
    /// one when it has one, else its left (or top) one; nvim's <M-H/J/K/L>
    /// follow the same rule (nvim/lua/config/zellij.lua). With `editor_first`
    /// an nvim pane gets Alt+Shift+key instead, and calls back with
    /// `resize-pane` when it has no window divider in that direction.
    fn resize(&self, direction: Direction, editor_first: bool) {
        let Ok((tab, pane)) = get_focused_pane_info() else {
            return;
        };
        if editor_first && is_editor(pane) {
            write_to_pane_id(vec![0x1b, key_for(direction).to_ascii_uppercase()], pane);
            return;
        }

        let info = self.panes.panes.get(&tab).and_then(|panes| {
            panes.iter().find(|p| match pane {
                PaneId::Terminal(id) => !p.is_plugin && p.id == id,
                PaneId::Plugin(id) => p.is_plugin && p.id == id,
            })
        });
        let viewport = self.tabs.iter().find(|t| t.position == tab);
        let (Some(info), Some(viewport)) = (info, viewport) else {
            // Unknown geometry: Zellij's own rule for the key.
            resize_focused_pane_with_direction(Resize::Increase, direction);
            return;
        };

        let (resize, edge) = divider_move(
            direction,
            info.pane_x + info.pane_columns < viewport.viewport_columns,
            info.pane_y + info.pane_rows < viewport.viewport_rows,
        );
        self.log(|| format!("resize {direction:?}: {resize:?} {edge:?}"));
        resize_focused_pane_with_direction(resize, edge);
    }

    /// Remove lobbies nobody is in. A lobby is the hub's full-screen session
    /// (`zj` without arguments, the Windows Terminal profile). The hub ends
    /// its lobby itself when it leaves, by closing its only pane; this is for
    /// the ones left behind, such as a lobby whose window was closed. They
    /// are removed explicitly, by name, never through Zellij's own rule for
    /// unused sessions.
    ///
    /// Two windows each have their own lobby with a client in it, so neither
    /// is touched. A lobby younger than `LOBBY_MIN_AGE_SECS` is left alone
    /// too: its client may still be connecting.
    fn sweep_lobbies(&mut self) {
        if !self.ready || get_focused_pane_info().is_err() {
            return;
        }
        let now = unix_now();
        if now.saturating_sub(self.swept_at) < LOBBY_SWEEP_EVERY_SECS {
            return;
        }
        self.swept_at = now;
        let Ok(sessions) = get_session_list() else { return };

        let abandoned: Vec<&str> = sessions
            .live_sessions
            .iter()
            .filter(|s| {
                s.name.starts_with(shell::LOBBY_PREFIX)
                    && s.connected_clients == 0
                    && s.creation_time.as_secs() >= LOBBY_MIN_AGE_SECS
            })
            .map(|s| s.name.as_str())
            .collect();
        if !abandoned.is_empty() {
            self.log(|| format!("sweeping lobbies {abandoned:?}"));
            if let Err(error) = kill_sessions(&abandoned) {
                eprintln!("pilot: could not stop lobbies {abandoned:?}: {error}");
            }
        }
        // Stopped lobbies, from this sweep or an earlier crash, must not
        // pile up as saved sessions.
        let saved = sessions.resurrectable_sessions.iter().map(|(name, _)| name.as_str());
        for lobby in abandoned.iter().copied().chain(saved).filter(|name| name.starts_with(shell::LOBBY_PREFIX)) {
            let _ = delete_dead_session(lobby);
        }
    }

    /// Carry out what the hub of another session asked of this one, now that
    /// a client is here: add the tab it opened, or stop the session it left
    /// (see pending.rs).
    fn run_pending(&mut self) {
        let Some(session) = &self.session else { return };
        if !self.ready || get_focused_pane_info().is_err() {
            return;
        }
        match pending::take(session) {
            Some(pending::Request::NewTab { layout }) => {
                new_tabs_with_layout(&layout);
            }
            Some(pending::Request::Kill { session }) => {
                if let Err(error) = kill_sessions(&[session.as_str()]) {
                    eprintln!("pilot: could not stop {session}: {error}");
                }
            }
            None => {}
        }
    }

    /// A pane that can take the Enter without anything reaching a program:
    /// a live terminal, not a held command pane (where Enter would run the
    /// command), whose foreground program is a plain shell (`SHELLS` do not
    /// use the kitty keyboard protocol, so an Enter without bytes writes
    /// nothing). The focused tab first, then the others.
    ///
    /// A resurrected session brings every pane back held ("press Enter to
    /// run"), plain shells included. Failing a running shell, a held pane
    /// whose command is a shell alone (no arguments) is used: the Enter
    /// starts that shell, which is what the user would do anyway. Held panes
    /// running anything else (a dev server, an agent, nvim) are never used.
    fn shell_pane(&self, focused_tab: usize) -> Option<u32> {
        let mut tabs: Vec<usize> = self.panes.panes.keys().copied().collect();
        tabs.sort_by_key(|tab| (*tab != focused_tab, *tab));
        let panes = || {
            tabs.iter()
                .flat_map(|tab| self.panes.panes[tab].iter())
                .filter(|p| !p.is_plugin && !p.exited && !p.is_suppressed)
        };
        let running = panes().filter(|p| !p.is_held).find(|p| {
            get_pane_running_command(PaneId::Terminal(p.id))
                .ok()
                .and_then(|argv| argv.first().map(|program| is_shell(program)))
                .unwrap_or(false)
        });
        let held = || {
            panes()
                .filter(|p| p.is_held)
                .find(|p| p.terminal_command.as_deref().is_some_and(is_shell))
        };
        running.or_else(held).map(|p| p.id)
    }

    /// Once there is a client and its tab has a shell pane, ask Zellij
    /// whether the session counts as used yet (see `Keep`).
    fn keep_session(&mut self) {
        if !self.ready || self.keep != Keep::Waiting {
            return;
        }
        let Ok((tab, _)) = get_focused_pane_info() else {
            return; // no client yet (a session started in the background)
        };
        if self.shell_pane(tab).is_some() {
            self.keep = Keep::Checking;
            get_session_suggestions(0);
        }
    }

    /// Send an Enter key event without bytes from the user's client in the
    /// shell pane, which marks the session as used, then (on ActionComplete)
    /// focus the pane that had it.
    fn mark_session_used(&mut self) {
        let Ok((tab, focused)) = get_focused_pane_info() else {
            self.keep = Keep::Waiting;
            return;
        };
        let Some(shell) = self.shell_pane(tab) else {
            self.keep = Keep::Waiting;
            return;
        };
        self.log(|| format!("marking the session as used through shell pane {shell}"));
        focus_terminal_pane(shell, false, false);
        run_action(
            actions::Action::Write {
                key_with_modifier: Some(KeyWithModifier::new(BareKey::Enter)),
                bytes: vec![],
                is_kitty_keyboard_protocol: false,
            },
            BTreeMap::from([(KEEP_CONTEXT.to_owned(), String::new())]),
        );
        self.keep = Keep::Marking(focused);
    }

    /// Go to the tab holding an activity, back where you came from if it is
    /// already showing, or start it in a new tab.
    ///
    /// Nothing is started with a session: often a question is a grep away and
    /// no agent is wanted, and the editor is the only thing a session opens
    /// with (zellij/decisions/0001-workspace-model.md).
    fn activity(&self, kind: Activity) {
        let existing = self.tabs.iter().find(|tab| tab.name == kind.name());
        self.log(|| format!("{kind:?}: tab {:?}, last {:?}", existing.map(|t| t.position), self.last_tab));

        match existing {
            // Already here: back to the tab this came from.
            Some(tab) if tab.active => {
                if let Some(back) = self.last_tab {
                    go_to_tab(back as u32 + 1);
                }
            }
            Some(tab) => go_to_tab(tab.position as u32 + 1),
            None => self.start_activity(kind),
        }
    }

    /// Open an activity in a new tab, in the focused pane's folder.
    fn start_activity(&self, kind: Activity) {
        let command = match kind {
            Activity::Editor => &self.editor_command,
            Activity::Agent => &self.agent_command,
            Activity::Git => &self.git_command,
        };
        let Some((program, args)) = command.split_first() else {
            eprintln!("pilot: no command configured for the {} tab", kind.name());
            return;
        };

        let cwd = get_focused_pane_info().ok().and_then(|(_, pane)| get_pane_cwd(pane).ok());
        let to_run = CommandToRun {
            path: PathBuf::from(program),
            args: args.to_vec(),
            cwd,
            border_style: None,
        };

        let (tab, pane) = open_command_pane_in_new_tab(to_run, BTreeMap::new());
        if let Some(tab) = tab {
            rename_tab_with_id(tab as u64, kind.name());
        }
        // The agent is found by pane title, not only by tab, because Neovim's
        // agent bridge pastes into it from another tab.
        if let (Activity::Agent, Some(PaneId::Terminal(id))) = (kind, pane) {
            rename_terminal_pane(id, AGENT_PANE);
        }
    }

    /// Move this client to another session, creating it or adding a tab to it
    /// from the layout in the payload (`-` for none).
    ///
    /// `zellij action switch-session` cannot do this from inside a pane: the
    /// server switches the client that sent the action, which for the CLI is
    /// its own short-lived connection, not the user's. A plugin instance
    /// belongs to the user's client, so `zj` sends the request here.
    ///
    /// Every client's instance gets the broadcast; only the one whose client
    /// is focused on the requesting pane (`pane` argument) acts.
    fn switch_session(&self, args: &BTreeMap<String, String>, payload: &str) {
        if let Some(origin) = args.get("pane").and_then(|p| p.parse::<u32>().ok()) {
            match get_focused_pane_info() {
                Ok((_, PaneId::Terminal(id))) if id == origin => {}
                _ => return,
            }
        }
        let Some(session) = args.get("session") else {
            eprintln!("pilot: switch needs a session argument");
            return;
        };

        let request = ConnectToSession {
            name: Some(session.clone()),
            tab_position: args.get("tab").and_then(|t| t.parse().ok()),
            layout: (payload != "-").then(|| LayoutInfo::Stringified(payload.to_owned())),
            cwd: args.get("cwd").map(PathBuf::from),
            ..Default::default()
        };
        self.log(|| format!("switch to {request:?}"));
        switch_session_with_options(request);
    }

}

/// Whether the pane's foreground program is one of `EDITORS`.
fn is_editor(pane: PaneId) -> bool {
    let Ok(argv) = get_pane_running_command(pane) else {
        return false;
    };
    argv.first().is_some_and(|program| EDITORS.contains(&program_name(program).as_str()))
}

/// `C:\Program Files\Neovim\bin\nvim.exe` -> `nvim`.
fn program_name(program: &str) -> String {
    let file = program.rsplit(['/', '\\']).next().unwrap_or(program).to_lowercase();
    file.strip_suffix(".exe").map(str::to_owned).unwrap_or(file)
}

/// Whether a program, or a whole command line, is one of `SHELLS` with no
/// arguments: `C:\...\pwsh.EXE` is, `pwsh -Command zjr dev` is not (its last
/// path segment is not a bare program name).
fn is_shell(command: &str) -> bool {
    SHELLS.contains(&program_name(command.trim()).as_str())
}

fn parse_direction(payload: &str) -> Option<Direction> {
    match payload.trim() {
        "left" => Some(Direction::Left),
        "right" => Some(Direction::Right),
        "up" => Some(Direction::Up),
        "down" => Some(Direction::Down),
        _ => None,
    }
}

/// The Zellij resize that moves a divider towards `direction`, given whether
/// the pane has a neighbour to its right and below. The right/bottom divider
/// is preferred: moving it towards the neighbour grows the pane, away
/// shrinks it. Without one, the left/top divider moves, which shrinks the
/// pane when it moves towards the far side.
fn divider_move(direction: Direction, has_right: bool, has_below: bool) -> (Resize, Direction) {
    match direction {
        Direction::Right if has_right => (Resize::Increase, Direction::Right),
        Direction::Right => (Resize::Decrease, Direction::Left),
        Direction::Left if has_right => (Resize::Decrease, Direction::Right),
        Direction::Left => (Resize::Increase, Direction::Left),
        Direction::Down if has_below => (Resize::Increase, Direction::Down),
        Direction::Down => (Resize::Decrease, Direction::Up),
        Direction::Up if has_below => (Resize::Decrease, Direction::Down),
        Direction::Up => (Resize::Increase, Direction::Up),
    }
}

/// The vi key Neovim maps for each direction.
fn key_for(direction: Direction) -> u8 {
    match direction {
        Direction::Left => b'h',
        Direction::Down => b'j',
        Direction::Up => b'k',
        Direction::Right => b'l',
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn program_name_strips_path_and_extension() {
        assert_eq!(program_name(r"C:\Program Files\Neovim\bin\nvim.exe"), "nvim");
        assert_eq!(program_name("/usr/bin/nvim"), "nvim");
        assert_eq!(program_name("NVIM.EXE"), "nvim");
        assert_eq!(program_name("pwsh"), "pwsh");
    }

    #[test]
    fn only_bare_shells_take_the_enter() {
        assert!(is_shell(r"C:\Users\me\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.EXE"));
        assert!(is_shell("bash"));
        assert!(is_shell(r"C:\Windows\System32\cmd.exe "));
        assert!(!is_shell("pwsh -NoLogo -Command zjr dev; exit $LASTEXITCODE"));
        assert!(!is_shell(r"C:\Program Files\Neovim\bin\nvim.exe"));
        assert!(!is_shell(r"C:\Users\me\.local\bin\opencode.exe"));
    }

    #[test]
    fn dividers_prefer_the_right_and_bottom_one() {
        // A left pane (neighbour on the right): Alt L grows it, Alt H shrinks it.
        assert_eq!(divider_move(Direction::Right, true, false), (Resize::Increase, Direction::Right));
        assert_eq!(divider_move(Direction::Left, true, false), (Resize::Decrease, Direction::Right));
        // A right pane: its left divider moves.
        assert_eq!(divider_move(Direction::Right, false, false), (Resize::Decrease, Direction::Left));
        assert_eq!(divider_move(Direction::Left, false, false), (Resize::Increase, Direction::Left));
        // A top pane grows downwards; a bottom pane's top divider moves.
        assert_eq!(divider_move(Direction::Down, false, true), (Resize::Increase, Direction::Down));
        assert_eq!(divider_move(Direction::Up, false, false), (Resize::Increase, Direction::Up));
    }

    #[test]
    fn directions_parse_and_map_to_vi_keys() {
        assert_eq!(parse_direction("left").map(key_for), Some(b'h'));
        assert_eq!(parse_direction(" down ").map(key_for), Some(b'j'));
        assert_eq!(parse_direction("sideways"), None);
    }
}
