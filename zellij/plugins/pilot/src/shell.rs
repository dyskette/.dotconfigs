//! The hub as a Zellij plugin view: this file is the only part of the hub
//! that talks to Zellij. It keeps the hub (`crate::hub`) supplied with what
//! Zellij reports, prints the frame the hub draws, and carries out the
//! effects the hub asks for.
//!
//! The same wasm runs as pilot (headless, one per session) and as the hub
//! (a pane, opened on demand); the `view "hub"` setting picks this one.

use std::collections::BTreeMap;
use std::time::Duration;

use zellij_tile::prelude::*;

use crate::hub::model::{OpenPlan, ProjectEntry, Row, RowId, RowKind, SessionEntry, Snapshot, TabEntry};
use crate::hub::schedule::Schedule;
use crate::hub::target::{self, Target};
use crate::hub::view::{self, Frame, Preview, Style};
use crate::hub::{Effect, Hub, Key};
use crate::pending::{self, Request};

/// Sessions whose name starts with this are lobbies: the hub's own full
/// screen sessions, never listed and swept when nobody is in them.
pub const LOBBY_PREFIX: &str = "lobby-";

/// A file with this prefix and the lobby's name, in Zellij's temp folder,
/// says the lobby was quit with q rather than left for a session.
const QUIT_MARKER_PREFIX: &str = "hub-quit-";

/// Context tag of the project scan, to recognise its result.
const PROJECTS_CONTEXT: &str = "hub-projects";
/// Context tag of the folder check behind "new": its value is unused.
const FOLDER_CONTEXT: &str = "hub-folder";
/// Context tag of a `zellij` command run for another session; its value
/// says what was being done, for the message when it fails.
const ACTION_CONTEXT: &str = "hub-action";
/// The layout a project opens with (layouts/service.kdl).
const SERVICE_LAYOUT: &str = "service";
/// Where the last project list is kept so the hub can show it at once.
const PROJECTS_CACHE: &str = "/cache/hub-projects.txt";
/// The hub's only timer (see hub/schedule.rs). The cursor must rest on a row
/// for one to two ticks before its preview is fetched.
const TICK_SECS: f64 = 0.1;
/// Ticks between reads of the session list (about a second). Zellij reports
/// changes with SessionUpdate, but not promptly after the hub's own actions,
/// and attention markers should stay current.
const TICKS_PER_REFRESH: u32 = 10;

pub struct HubShell {
    hub: Hub,
    /// First visible row of the list.
    scroll: usize,
    live: Vec<SessionInfo>,
    saved: Vec<(String, Duration)>,
    /// Session names, most recently used first.
    history: Vec<String>,
    projects: Vec<ProjectEntry>,
    /// The projects root, as the scan reported it.
    root: String,
    /// The command that prints the projects root and the ranked projects
    /// (`projects_command` setting).
    projects_command: Vec<String>,
    preview: Preview,
    /// The row the preview on screen belongs to.
    preview_of: Option<RowId>,
    /// The row a preview was asked for and is still wanted.
    preview_wanted: Option<RowId>,
    schedule: Schedule,
    /// Whether the tick timer runs; it is started once and re-armed by each
    /// tick, so exactly one is ever pending.
    ticking: bool,
    ready: bool,
}

impl HubShell {
    pub fn load(configuration: &BTreeMap<String, String>) -> Self {
        let lobby = configuration.get("lobby").is_some_and(|v| v == "true");
        let projects_command = configuration
            .get("projects_command")
            .map(|c| c.split_whitespace().map(str::to_owned).collect())
            .unwrap_or_default();

        request_permission(crate::PERMISSIONS);

        subscribe(&[
            EventType::Key,
            EventType::SessionUpdate,
            EventType::SessionHistoryUpdate,
            EventType::SessionPreview,
            EventType::SavedSessionPreview,
            EventType::RunCommandResult,
            EventType::Timer,
            EventType::PermissionRequestResult,
        ]);

        let mut shell = HubShell {
            hub: Hub::new(lobby),
            scroll: 0,
            live: Vec::new(),
            saved: Vec::new(),
            history: Vec::new(),
            projects: Vec::new(),
            root: String::new(),
            projects_command,
            preview: Preview::default(),
            preview_of: None,
            preview_wanted: None,
            schedule: Schedule::new(TICKS_PER_REFRESH),
            ticking: false,
            ready: false,
        };
        // The list from last time, so projects are there on the first paint.
        if let Ok(cached) = std::fs::read_to_string(PROJECTS_CACHE) {
            shell.set_projects(&cached);
        }
        shell
    }

    /// Returns whether the hub has to be drawn again.
    pub fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                self.ready = true;
                self.claim_pane();
                self.pull_sessions();
                self.scan_projects();
                self.refresh();
                if !self.ticking {
                    self.ticking = true;
                    set_timeout(TICK_SECS);
                }
            }
            // Only redraw when the list changed: every redraw of the hub makes
            // Zellij report the sessions again, so redrawing on each report
            // fed a loop that kept the plugin thread busy and keys waiting.
            Event::SessionUpdate(live, saved) => {
                self.live = live;
                self.saved = saved;
                return self.refresh();
            }
            Event::SessionHistoryUpdate(history) => {
                self.history = std::iter::once(history.current).chain(history.previous).chain(history.back).collect();
                return self.refresh();
            }
            Event::RunCommandResult(code, stdout, _, context) if context.contains_key(PROJECTS_CONTEXT) => {
                if code == Some(0) {
                    let listing = String::from_utf8_lossy(&stdout).into_owned();
                    self.set_projects(&listing);
                    // Best effort: without the cache the first paint has no projects.
                    let _ = std::fs::write(PROJECTS_CACHE, listing);
                    self.refresh();
                }
            }
            Event::RunCommandResult(code, stdout, _, context) if context.contains_key(FOLDER_CONTEXT) => {
                let folder = String::from_utf8_lossy(&stdout).trim().to_owned();
                if code == Some(0) && !folder.is_empty() {
                    self.open_target(target::folder_target(&folder, &self.root));
                } else {
                    self.hub.set_notice("No such folder".to_owned());
                }
            }
            Event::RunCommandResult(code, _, stderr, context) if context.contains_key(ACTION_CONTEXT) => {
                if code != Some(0) {
                    let what = context.get(ACTION_CONTEXT).cloned().unwrap_or_default();
                    let why = String::from_utf8_lossy(&stderr);
                    self.hub.set_notice(format!("Could not {what}: {}", why.trim()));
                }
            }
            Event::Key(key) => {
                for effect in self.hub.handle_key(translate_key(&key)) {
                    self.run(effect);
                }
                self.sync_preview();
            }
            // The only timer is the tick; its reported length is ignored.
            Event::Timer(_) => {
                set_timeout(TICK_SECS);
                let tick = self.schedule.tick();
                if tick.fetch_preview {
                    self.fetch_preview();
                }
                if !tick.refresh {
                    return false; // nothing on screen changed
                }
                self.pull_sessions();
                return self.refresh();
            }
            Event::SessionPreview(report) => {
                if self.wants_preview_of(&report.session_name) {
                    let screen = strip_escapes(&report.contents);
                    self.preview.lines = screen.lines().map(str::to_owned).collect();
                }
            }
            Event::SavedSessionPreview(report) => {
                if self.wants_preview_of(&report.session_name) {
                    self.preview.lines = saved_preview_lines(&report);
                }
            }
            _ => return false,
        }
        true
    }

    pub fn render(&mut self, rows: usize, cols: usize) {
        let saved = self.saved.clone();
        let ages = move |name: &str| saved.iter().find(|(saved, _)| saved == name).map(|(_, age)| age.as_secs());

        // The list height depends on the layout, which depends on the size:
        // lay out once to learn it, then scroll and draw.
        let list_height = view::frame(&self.hub, &self.preview, cols, rows, self.scroll, &ages).list_height;
        self.hub.set_half_page(list_height / 2);
        self.scroll = view::scroll_for(self.hub.rows(), self.hub.selected_index(), self.scroll, list_height);

        let frame = view::frame(&self.hub, &self.preview, cols, rows, self.scroll, &ages);
        // Commands before any drawing: both travel over the plugin's stdout,
        // and a command sent after printed text arrives corrupted.
        show_cursor(frame.cursor);
        print_frame(&frame);
    }

    /// Name the pane, and as a popup take most of the screen: a keybinding's
    /// size settings are ignored for plugins (Zellij 0.46.0), so the hub
    /// sizes its own floating pane. The lobby is a tiled pane already.
    fn claim_pane(&self) {
        let id = get_plugin_ids().plugin_id;
        rename_plugin_pane(id, "Sessions & projects");
        if self.hub.is_lobby() {
            return;
        }
        let percent = |value: &str| Some(value.to_owned());
        if let Some(place) = FloatingPaneCoordinates::new(percent("8%"), percent("8%"), percent("84%"), percent("84%"), None, None) {
            change_floating_panes_coordinates(vec![(PaneId::Plugin(id), place)]);
        }
    }

    // --- Data ------------------------------------------------------------------------

    /// Read the sessions from Zellij now.
    fn pull_sessions(&mut self) {
        if let Ok(sessions) = get_session_list() {
            self.live = sessions.live_sessions;
            self.saved = sessions.resurrectable_sessions;
        }
    }

    fn set_projects(&mut self, listing: &str) {
        let (root, projects) = parse_projects(listing);
        self.root = root;
        self.projects = projects;
    }

    fn scan_projects(&self) {
        let Some((program, args)) = self.projects_command.split_first() else { return };
        let command: Vec<&str> = std::iter::once(program.as_str()).chain(args.iter().map(String::as_str)).collect();
        run_command(&command, BTreeMap::from([(PROJECTS_CONTEXT.to_owned(), String::new())]));
    }

    /// Rebuild the hub's snapshot from what Zellij last reported. Returns
    /// whether the list changed and has to be drawn again.
    fn refresh(&mut self) -> bool {
        let recency = |name: &str| {
            let position = self.history.iter().position(|seen| seen == name).unwrap_or(self.history.len());
            (self.history.len() - position) as u64
        };
        let listed = |name: &str| !name.starts_with(LOBBY_PREFIX);

        let mut sessions: Vec<SessionEntry> = self
            .live
            .iter()
            .filter(|s| listed(&s.name))
            .map(|s| SessionEntry {
                name: s.name.clone(),
                running: true,
                current: s.is_current_session,
                tabs: s
                    .tabs
                    .iter()
                    .map(|t| TabEntry {
                        id: t.tab_id,
                        position: t.position,
                        name: t.name.clone(),
                        attention: t.attention.counts.needs_you + t.attention.counts.failed,
                        working: t.attention.counts.working > 0,
                    })
                    .collect(),
                last_used: recency(&s.name),
                saved_secs_ago: 0,
            })
            .collect();
        let saved: Vec<SessionEntry> = self
            .saved
            .iter()
            .filter(|(name, _)| listed(name) && !sessions.iter().any(|s| &s.name == name))
            .map(|(name, age)| SessionEntry {
                name: name.clone(),
                running: false,
                current: false,
                tabs: Vec::new(),
                last_used: 0,
                saved_secs_ago: age.as_secs(),
            })
            .collect();
        sessions.extend(saved);

        let changed = self.hub.set_snapshot(Snapshot { sessions, projects: self.projects.clone() });
        if changed {
            self.sync_preview();
        }
        changed
    }

    // --- Preview -----------------------------------------------------------------------

    fn wants_preview_of(&self, session: &str) -> bool {
        match &self.preview_wanted {
            Some(RowId::Session(name)) | Some(RowId::Tab { session: name, .. }) => name == session,
            _ => false,
        }
    }

    /// After the selection may have changed: describe the row at once, and
    /// for rows with a screen ask for it once the cursor has rested.
    fn sync_preview(&mut self) {
        let selected = self.hub.selected().cloned();
        let id = selected.as_ref().and_then(Row::id);
        if id == self.preview_of {
            return;
        }
        self.preview_of = id.clone();
        self.preview = selected.as_ref().map(view::describe).unwrap_or_default();

        let has_screen = matches!(
            selected.as_ref().map(|row| &row.kind),
            Some(RowKind::Session { current: false, .. } | RowKind::Tab { .. })
        );
        self.preview_wanted = if has_screen && self.hub.preview_enabled() { id } else { None };
        if self.preview_wanted.is_some() {
            self.schedule.want_preview();
        } else {
            self.schedule.cancel_preview();
        }
    }

    /// The cursor rested: fetch the preview if it is still on that row.
    fn fetch_preview(&mut self) {
        let Some(row) = self.hub.selected() else { return };
        if row.id() != self.preview_wanted {
            return;
        }
        match &row.kind {
            RowKind::Session { name, running: true, .. } => get_session_preview(name, None, None),
            RowKind::Session { name, .. } => get_saved_session_preview(name),
            RowKind::Tab { session, position, .. } => get_session_preview(session, Some(*position), None),
            _ => {}
        }
    }

    // --- Effects -------------------------------------------------------------------------

    fn run(&mut self, effect: Effect) {
        match effect {
            Effect::Close => close_self(),
            Effect::Quit => {
                // Tell the loop that started this lobby (zj: zellij/bin/zj on
                // Linux, powershell/Zellij.psm1 on Windows) that it was left
                // on purpose: the plugin's /tmp is Zellij's temp folder on
                // the host.
                if let Some(lobby) = self.live.iter().find(|s| s.is_current_session) {
                    let _ = std::fs::write(format!("/tmp/{QUIT_MARKER_PREFIX}{}", lobby.name), "");
                }
                quit_zellij();
            }
            Effect::Open(plan) => self.open(plan),
            Effect::Kill { session } => {
                let result = kill_sessions(&[session.as_str()]);
                if result.is_ok() {
                    // List it as saved at once: a second dd must find it
                    // saved, and ask, even before Zellij's list catches up.
                    self.live.retain(|s| s.name != session);
                    if !self.saved.iter().any(|(name, _)| name == &session) {
                        self.saved.push((session.clone(), Duration::ZERO));
                    }
                    self.refresh();
                }
                self.report(result, "stop the session");
            }
            Effect::Forget { session } => {
                let result = delete_dead_session(&session);
                if result.is_ok() {
                    self.saved.retain(|(name, _)| name != &session);
                    self.refresh();
                }
                self.report(result, "delete the session");
            }
            Effect::KillCurrent { session, switch_to: Some(next) } => {
                // The session can only be stopped once the client has left
                // it: the pilot of the next session does it on arrival.
                match pending::leave(&next, &Request::Kill { session }) {
                    Ok(()) => {
                        switch_session(Some(&next));
                        close_self();
                    }
                    Err(error) => self.hub.set_notice(format!("Could not leave the request: {error}")),
                }
            }
            // Nowhere else to go: the client ends up outside Zellij (back
            // in the lobby when it was started from the Windows Terminal
            // profile).
            Effect::KillCurrent { session, switch_to: None } => {
                self.report(kill_sessions(&[session.as_str()]), "stop the session");
            }
            Effect::CloseTab { session, id } => {
                if self.is_current(&session) {
                    close_tab_with_id(id as u64);
                } else {
                    self.zellij_in(&session, &["close-tab-by-id", &id.to_string()], "close the tab");
                }
            }
            Effect::RenameSession { from, to } => {
                if self.is_current(&from) {
                    rename_session(&to);
                } else if self.live.iter().any(|s| s.name == from) {
                    self.zellij_in(&from, &["rename-session", &to], "rename the session");
                } else {
                    // Zellij can only rename a session that is running.
                    self.hub.set_notice(format!("{from} is saved: open it to rename it"));
                }
            }
            Effect::RenameTab { session, id, to } => {
                if self.is_current(&session) {
                    rename_tab_with_id(id as u64, &to);
                } else {
                    self.zellij_in(&session, &["rename-tab-by-id", &id.to_string(), &to], "rename the tab");
                }
            }
        }
    }

    fn is_current(&self, session: &str) -> bool {
        self.live.iter().any(|s| s.is_current_session && s.name == session)
    }

    fn report(&mut self, result: Result<(), String>, what: &str) {
        if let Err(error) = result {
            self.hub.set_notice(format!("Could not {what}: {error}"));
        }
    }

    /// Run `zellij action ...` in another session. The plugin API only acts
    /// on the session the plugin is in; the CLI reaches any running one.
    fn zellij_in(&self, session: &str, action: &[&str], what: &str) {
        let command: Vec<&str> = ["zellij", "--session", session, "action"].into_iter().chain(action.iter().copied()).collect();
        run_command(&command, BTreeMap::from([(ACTION_CONTEXT.to_owned(), what.to_owned())]));
    }

    fn open(&mut self, plan: OpenPlan) {
        match plan {
            OpenPlan::Stay => {}
            OpenPlan::GoToTab { position, .. } => switch_tab_to(position as u32 + 1),
            OpenPlan::Attach { session, tab } => switch_session_with_focus(&session, tab.map(|(position, _)| position), None),
            OpenPlan::Resurrect { session } => switch_session(Some(&session)),
            OpenPlan::Scratch { session } => {
                let home = std::env::var("USERPROFILE").or_else(|_| std::env::var("HOME")).ok();
                switch_session_with_cwd(Some(&session), home.map(std::path::PathBuf::from));
            }
            OpenPlan::NewTab(target) | OpenPlan::ResurrectAndNewTab(target) | OpenPlan::NewSession(target) => {
                return self.open_target(target);
            }
            OpenPlan::Path { text } => return self.check_folder(&text),
        }
        close_self();
    }

    /// "New" with a folder: resolve it on the host first (~, a relative
    /// path, whether it exists); the result arrives as RunCommandResult.
    ///
    /// The plugin is wasm, so the shell that resolves it is the host's:
    /// pwsh on Windows, sh on Linux.
    fn check_folder(&mut self, text: &str) {
        let cwd = get_plugin_ids().initial_cwd;
        let command: Vec<&str> = if host_is_windows(&cwd) {
            let script = "$p = $env:ZJ_HUB_FOLDER; if (Test-Path -LiteralPath $p -PathType Container) { \
                          (Resolve-Path -LiteralPath $p).ProviderPath } else { exit 1 }";
            vec!["pwsh", "-NoLogo", "-NoProfile", "-Command", script]
        } else {
            // POSIX sh: ~ is only expanded by an interactive shell, so it is
            // expanded here; cd ... && pwd -P prints the folder as an
            // absolute path, and fails when it is not one.
            let script = "p=$ZJ_HUB_FOLDER; \
                          case $p in '~') p=$HOME ;; '~/'*) p=$HOME/${p#'~/'} ;; esac; \
                          [ -d \"$p\" ] && cd \"$p\" && pwd -P";
            vec!["sh", "-c", script]
        };
        run_command_with_env_variables_and_cwd(
            &command,
            BTreeMap::from([("ZJ_HUB_FOLDER".to_owned(), text.to_owned())]),
            cwd,
            BTreeMap::from([(FOLDER_CONTEXT.to_owned(), String::new())]),
        );
        self.hub.set_notice(format!("Opening {text}…"));
    }

    /// Open a folder's session and tab, whatever state they are in: the
    /// same decisions as `zj` (powershell/Zellij.psm1, Open-ZjTarget).
    fn open_target(&mut self, target: Target) {
        let session = self.live.iter().find(|s| s.name == target.session);
        let open_tab = session.and_then(|s| s.tabs.iter().find(|t| t.name == target.tab).map(|t| t.position));
        let current = session.is_some_and(|s| s.is_current_session);

        // The tab is open already: just go there.
        if let Some(position) = open_tab {
            if current {
                switch_tab_to(position as u32 + 1);
            } else {
                switch_session_with_focus(&target.session, Some(position), None);
            }
            return close_self();
        }

        let layout = match dump_layout(SERVICE_LAYOUT).and_then(|template| target::service_layout(&template, &target)) {
            Ok(layout) => layout,
            Err(error) => return self.hub.set_notice(format!("Could not read the service layout: {error}")),
        };

        if current {
            new_tabs_with_layout(&layout);
        } else if session.is_some() || self.saved.iter().any(|(name, _)| name == &target.session) {
            // A running or saved session: the tab is added by its pilot
            // once this client is in (see pending.rs).
            if let Err(error) = pending::leave(&target.session, &Request::NewTab { layout }) {
                return self.hub.set_notice(format!("Could not leave the request: {error}"));
            }
            switch_session(Some(&target.session));
        } else {
            switch_session_with_options(ConnectToSession {
                name: Some(target.session.clone()),
                layout: Some(LayoutInfo::Stringified(layout)),
                cwd: Some(std::path::PathBuf::from(&target.dir)),
                ..Default::default()
            });
        }
        close_self();
    }
}

/// Whether the host runs Windows, told from one of its paths: the plugin is
/// wasm, so the target it was built for says nothing about the machine.
fn host_is_windows(path: &std::path::Path) -> bool {
    let text = path.to_string_lossy();
    let drive = matches!(text.as_bytes(), [letter, b':', ..] if letter.is_ascii_alphabetic());
    drive || text.contains('\\')
}

/// The scan's output: `root=<folder>` then one project per line, relative to
/// the root with `/` separators, most used first.
fn parse_projects(listing: &str) -> (String, Vec<ProjectEntry>) {
    let mut lines = listing.lines().map(str::trim).filter(|l| !l.is_empty());
    let Some(root) = lines.next().and_then(|first| first.strip_prefix("root=")) else {
        return (String::new(), Vec::new());
    };
    let root = root.trim_end_matches(['/', '\\']);
    let separator = if root.contains('\\') { "\\" } else { "/" };
    let projects = lines
        .map(|rel| {
            let rel = rel.replace('\\', "/");
            let dir = format!("{root}{separator}{}", rel.replace('/', separator));
            ProjectEntry { rel, dir }
        })
        .collect();
    (root.to_owned(), projects)
}

/// A saved session has no screen: list its tabs and what ran in them.
fn saved_preview_lines(report: &SavedSessionPreview) -> Vec<String> {
    if let Some(error) = &report.error {
        return vec![error.clone()];
    }
    let mut lines = vec!["Enter: resurrect (commands wait for Enter)".to_owned(), String::new()];
    if let Some(folder) = &report.folder {
        lines.push(format!("Folder   {folder}"));
        lines.push(String::new());
    }
    for tab in &report.tabs {
        lines.push(format!("{} {}", if tab.focused { "▾" } else { "▸" }, tab.name));
        for pane in &tab.panes {
            let what = pane.command.as_deref().or(pane.title.as_deref()).unwrap_or("shell");
            lines.push(format!("    {what}"));
        }
    }
    lines
}

/// Screen contents may carry colour and cursor sequences; the preview is
/// drawn as plain text, so CSI and OSC sequences are dropped.
fn strip_escapes(text: &str) -> String {
    let mut plain = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '\u{1b}' {
            if c != '\r' {
                plain.push(c);
            }
            continue;
        }
        match chars.next() {
            // CSI: parameters, then a final byte in @..~
            Some('[') => {
                for next in chars.by_ref() {
                    if ('@'..='~').contains(&next) {
                        break;
                    }
                }
            }
            // OSC: up to BEL or ESC \
            Some(']') => {
                while let Some(next) = chars.next() {
                    if next == '\u{7}' || (next == '\u{1b}' && chars.next_if_eq(&'\\').is_some()) {
                        break;
                    }
                }
            }
            _ => {} // a two-character sequence: both dropped
        }
    }
    plain
}

/// Zellij's key event as the hub's key. Shifted letters arrive either as the
/// capital itself or as the letter with Shift, depending on the terminal.
fn translate_key(key: &KeyWithModifier) -> Key {
    let only = |modifier: KeyModifier| key.key_modifiers.len() == 1 && key.key_modifiers.contains(&modifier);
    let plain = key.key_modifiers.is_empty();
    match key.bare_key {
        BareKey::Char(c) if plain => Key::Char(c),
        BareKey::Char(c) if only(KeyModifier::Shift) => Key::Char(c.to_uppercase().next().unwrap_or(c)),
        BareKey::Char(c) if only(KeyModifier::Ctrl) => Key::Ctrl(c.to_ascii_lowercase()),
        BareKey::Enter if plain => Key::Enter,
        BareKey::Esc if plain => Key::Esc,
        BareKey::Backspace if plain => Key::Backspace,
        BareKey::Up if plain => Key::Up,
        BareKey::Down if plain => Key::Down,
        _ => Key::Other,
    }
}

/// Print a frame with Zellij's themed text component.
fn print_frame(frame: &Frame) {
    for line in &frame.lines {
        let mut content = line.text();
        if line.selected {
            // Pad so the selection bar spans the row.
            let length = content.chars().count();
            content.extend(std::iter::repeat_n(' ', line.width.saturating_sub(length)));
        }
        let mut text = Text::from(content);
        let mut at = 0;
        for span in &line.spans {
            let range = at..at + span.text.chars().count();
            at = range.end;
            text = match span.style {
                Style::Plain => text,
                Style::Dim => text.dim_range(range),
                Style::Accent(level) => text.color_range(level as usize, range),
                Style::Good => text.success_color_range(range),
                Style::Bad => text.error_color_range(range),
            };
        }
        if line.selected {
            text = text.selected();
        }
        print_text_with_coordinates(text, line.x, line.y, Some(line.width), Some(1));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_project_scan_is_parsed_with_the_roots_separator() {
        let (root, projects) = parse_projects("root=C:\\Users\\me\\Projects\\\r\nacme/cerberus\r\nsentinel\r\n\r\n");
        assert_eq!(root, r"C:\Users\me\Projects");
        assert_eq!(projects.len(), 2);
        assert_eq!(projects[0].rel, "acme/cerberus");
        assert_eq!(projects[0].dir, r"C:\Users\me\Projects\acme\cerberus");
        assert_eq!(projects[1].dir, r"C:\Users\me\Projects\sentinel");

        let (_, unix) = parse_projects("root=/home/me/src\nacme/api\n");
        assert_eq!(unix[0].dir, "/home/me/src/acme/api");
    }

    #[test]
    fn the_host_is_told_from_its_paths() {
        use std::path::Path;
        assert!(host_is_windows(Path::new(r"C:\Users\me\Projects")));
        assert!(host_is_windows(Path::new(r"\\server\share\work")));
        assert!(!host_is_windows(Path::new("/home/me/Proyectos")));
        assert!(!host_is_windows(Path::new("/var/home/me")));
    }

    #[test]
    fn a_listing_without_a_root_is_ignored() {
        assert!(parse_projects("acme/cerberus\n").1.is_empty());
        assert!(parse_projects("").1.is_empty());
    }

    #[test]
    fn escape_sequences_are_removed_from_previews() {
        assert_eq!(strip_escapes("\u{1b}[1;32mok\u{1b}[0m done\r\n"), "ok done\n");
        assert_eq!(strip_escapes("a\u{1b}]0;title\u{7}b\u{1b}]8;;x\u{1b}\\c"), "abc");
        assert_eq!(strip_escapes("plain"), "plain");
    }

    #[test]
    fn keys_are_translated_whichever_way_shift_is_reported() {
        let key = |bare: BareKey, modifiers: &[KeyModifier]| {
            let mut key = KeyWithModifier::new(bare);
            key.key_modifiers = modifiers.iter().copied().collect();
            translate_key(&key)
        };
        assert_eq!(key(BareKey::Char('j'), &[]), Key::Char('j'));
        assert_eq!(key(BareKey::Char('G'), &[]), Key::Char('G'));
        assert_eq!(key(BareKey::Char('g'), &[KeyModifier::Shift]), Key::Char('G'));
        assert_eq!(key(BareKey::Char('D'), &[KeyModifier::Ctrl]), Key::Ctrl('d'));
        assert_eq!(key(BareKey::Enter, &[]), Key::Enter);
        assert_eq!(key(BareKey::Enter, &[KeyModifier::Alt]), Key::Other);
        assert_eq!(key(BareKey::Char('x'), &[KeyModifier::Alt]), Key::Other);
    }
}
