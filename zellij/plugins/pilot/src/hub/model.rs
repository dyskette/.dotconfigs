//! The hub's list: running sessions, saved sessions and projects as one set
//! of rows, and what opening each row does.
//!
//! With an empty filter the rows come in sections (Running, Saved,
//! Projects). With a filter they are one list ranked by match quality, and
//! sessions whose tabs match are expanded to those tabs.

use std::collections::BTreeSet;

use super::fuzzy;
use super::target::{self, Target};

/// Saved sessions older than this sink to the bottom of their section. They
/// are never deleted automatically.
pub const STALE_AFTER_SECS: u64 = 14 * 24 * 60 * 60;

/// A tab of a running session.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TabEntry {
    /// Zellij's stable tab id (for closing and renaming).
    pub id: usize,
    /// Position in the tab bar (for focusing).
    pub position: usize,
    pub name: String,
    /// Panes in the tab that need the user.
    pub attention: usize,
    /// Whether a program in the tab reports that it is working.
    pub working: bool,
}

/// A session Zellij knows: running, or saved for resurrection.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SessionEntry {
    pub name: String,
    pub running: bool,
    /// The session the hub was opened from.
    pub current: bool,
    /// Empty for saved sessions.
    pub tabs: Vec<TabEntry>,
    /// Larger is more recent; orders the running sessions.
    pub last_used: u64,
    /// Seconds since a saved session was last alive.
    pub saved_secs_ago: u64,
}

impl SessionEntry {
    pub fn attention(&self) -> usize {
        self.tabs.iter().map(|t| t.attention).sum()
    }
    pub fn working(&self) -> bool {
        self.tabs.iter().any(|t| t.working)
    }
}

/// A project folder under the projects root, in the order to show them
/// (most used first).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProjectEntry {
    /// Path relative to the root, `/` separated.
    pub rel: String,
    /// Absolute path.
    pub dir: String,
}

/// Everything the hub lists, as last reported by Zellij and the project scan.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Snapshot {
    pub sessions: Vec<SessionEntry>,
    pub projects: Vec<ProjectEntry>,
}

/// Whether a project's client session exists.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SessionState {
    Running,
    Saved,
    Missing,
}

/// Identity of a selectable row, stable across list rebuilds.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum RowId {
    Session(String),
    Tab { session: String, id: usize },
    Project(String),
    Create,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RowKind {
    /// A dim section title; not selectable.
    Header(&'static str),
    Session {
        name: String,
        running: bool,
        current: bool,
        /// A saved session not opened in `STALE_AFTER_SECS`.
        stale: bool,
        /// Whether its tab rows follow.
        expanded: bool,
        tabs: usize,
    },
    Tab {
        session: String,
        session_current: bool,
        id: usize,
        position: usize,
        name: String,
    },
    Project {
        rel: String,
        target: Target,
        session: SessionState,
    },
    /// "+ create <name>": a new empty session named after the filter text.
    Create { name: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Row {
    pub kind: RowKind,
    pub attention: usize,
    pub working: bool,
}

impl Row {
    fn plain(kind: RowKind) -> Self {
        Row { kind, attention: 0, working: false }
    }

    pub fn id(&self) -> Option<RowId> {
        match &self.kind {
            RowKind::Header(_) => None,
            RowKind::Session { name, .. } => Some(RowId::Session(name.clone())),
            RowKind::Tab { session, id, .. } => Some(RowId::Tab { session: session.clone(), id: *id }),
            RowKind::Project { rel, .. } => Some(RowId::Project(rel.clone())),
            RowKind::Create { .. } => Some(RowId::Create),
        }
    }

    pub fn selectable(&self) -> bool {
        !matches!(self.kind, RowKind::Header(_))
    }

    /// Whether `l` opens the row instead of expanding it: everything but a
    /// running session with tabs.
    pub fn is_leaf(&self) -> bool {
        !matches!(&self.kind, RowKind::Session { running: true, tabs, .. } if *tabs > 0)
    }
}

/// What opening a row does. The hub picks the mechanism; `hint` says which.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OpenPlan {
    /// Nothing to switch to: the current session itself.
    Stay,
    /// A tab of the current session.
    GoToTab { position: usize, name: String },
    /// Another running session, at a tab or where it was left.
    Attach { session: String, tab: Option<(usize, String)> },
    /// A saved session.
    Resurrect { session: String },
    /// A project whose client session is running without this service.
    NewTab(Target),
    /// A project whose client session is saved.
    ResurrectAndNewTab(Target),
    /// A project whose client has no session.
    NewSession(Target),
    /// An empty session with this name.
    Scratch { session: String },
    /// A folder typed at the "new" prompt, resolved when it is opened.
    Path { text: String },
}

impl OpenPlan {
    /// The hint shown next to Enter, so the effect is known before pressing it.
    pub fn hint(&self) -> String {
        match self {
            OpenPlan::Stay => "stay here".to_owned(),
            OpenPlan::GoToTab { name, .. } => format!("go to tab {name}"),
            OpenPlan::Attach { tab: Some((_, name)), session } => format!("attach {session}, tab {name}"),
            OpenPlan::Attach { session, tab: None } => format!("attach {session}"),
            OpenPlan::Resurrect { session } => format!("resurrect {session}"),
            OpenPlan::NewTab(t) => format!("new tab in {}", t.session),
            OpenPlan::ResurrectAndNewTab(t) => format!("resurrect {}, new tab {}", t.session, t.tab),
            OpenPlan::NewSession(t) => format!("new session \"{}\"", t.session),
            OpenPlan::Scratch { session } => format!("create \"{session}\""),
            OpenPlan::Path { text } => format!("open folder {text}"),
        }
    }
}

/// What opening `row` does; `None` for headers.
pub fn plan_for(row: &Row) -> Option<OpenPlan> {
    Some(match &row.kind {
        RowKind::Header(_) => return None,
        RowKind::Session { current: true, .. } => OpenPlan::Stay,
        RowKind::Session { name, running: true, .. } => OpenPlan::Attach { session: name.clone(), tab: None },
        RowKind::Session { name, .. } => OpenPlan::Resurrect { session: name.clone() },
        RowKind::Tab { session_current: true, position, name, .. } => {
            OpenPlan::GoToTab { position: *position, name: name.clone() }
        }
        RowKind::Tab { session, position, name, .. } => {
            OpenPlan::Attach { session: session.clone(), tab: Some((*position, name.clone())) }
        }
        RowKind::Project { target, session, .. } => match session {
            SessionState::Running => OpenPlan::NewTab(target.clone()),
            SessionState::Saved => OpenPlan::ResurrectAndNewTab(target.clone()),
            SessionState::Missing => OpenPlan::NewSession(target.clone()),
        },
        RowKind::Create { name } => OpenPlan::Scratch { session: name.clone() },
    })
}

fn session_row(session: &SessionEntry, expanded: bool) -> Row {
    Row {
        kind: RowKind::Session {
            name: session.name.clone(),
            running: session.running,
            current: session.current,
            stale: !session.running && session.saved_secs_ago > STALE_AFTER_SECS,
            expanded,
            tabs: session.tabs.len(),
        },
        attention: session.attention(),
        working: session.working(),
    }
}

fn tab_row(session: &SessionEntry, tab: &TabEntry) -> Row {
    Row {
        kind: RowKind::Tab {
            session: session.name.clone(),
            session_current: session.current,
            id: tab.id,
            position: tab.position,
            name: tab.name.clone(),
        },
        attention: tab.attention,
        working: tab.working,
    }
}

/// Projects not open yet, each with the state of its client session. A
/// project whose tab is open in its running session is left out: that tab's
/// row stands for it.
fn open_projects(snapshot: &Snapshot) -> Vec<Row> {
    snapshot
        .projects
        .iter()
        .filter_map(|project| {
            let target = target::project_target(&project.rel, &project.dir);
            let session = snapshot.sessions.iter().find(|s| s.name == target.session);
            let state = match session {
                Some(s) if s.running => {
                    if s.tabs.iter().any(|t| t.name == target.tab) {
                        return None;
                    }
                    SessionState::Running
                }
                Some(_) => SessionState::Saved,
                None => SessionState::Missing,
            };
            Some(Row::plain(RowKind::Project { rel: project.rel.clone(), target, session: state }))
        })
        .collect()
}

/// Running sessions, most recently used first (the current one leads).
fn running(snapshot: &Snapshot) -> Vec<&SessionEntry> {
    let mut sessions: Vec<&SessionEntry> = snapshot.sessions.iter().filter(|s| s.running).collect();
    sessions.sort_by(|a, b| b.current.cmp(&a.current).then(b.last_used.cmp(&a.last_used)).then(a.name.cmp(&b.name)));
    sessions
}

/// Saved sessions, most recently alive first, stale ones last.
fn saved(snapshot: &Snapshot) -> Vec<&SessionEntry> {
    let mut sessions: Vec<&SessionEntry> = snapshot.sessions.iter().filter(|s| !s.running).collect();
    sessions.sort_by(|a, b| a.saved_secs_ago.cmp(&b.saved_secs_ago).then(a.name.cmp(&b.name)));
    sessions
}

/// The rows to show. `expanded` holds the sessions the user unfolded.
pub fn build_rows(snapshot: &Snapshot, query: &str, expanded: &BTreeSet<String>) -> Vec<Row> {
    if query.trim().is_empty() {
        sectioned(snapshot, expanded)
    } else {
        ranked(snapshot, query, expanded)
    }
}

fn sectioned(snapshot: &Snapshot, expanded: &BTreeSet<String>) -> Vec<Row> {
    let mut rows = Vec::new();
    let section = |title: &'static str, items: Vec<Row>, rows: &mut Vec<Row>| {
        if !items.is_empty() {
            rows.push(Row::plain(RowKind::Header(title)));
            rows.extend(items);
        }
    };

    let mut live = Vec::new();
    for session in running(snapshot) {
        let open = expanded.contains(&session.name);
        live.push(session_row(session, open));
        if open {
            live.extend(session.tabs.iter().map(|tab| tab_row(session, tab)));
        }
    }
    section("Running", live, &mut rows);
    section("Saved", saved(snapshot).into_iter().map(|s| session_row(s, false)).collect(), &mut rows);
    section("Projects", open_projects(snapshot), &mut rows);
    rows
}

fn ranked(snapshot: &Snapshot, query: &str, expanded: &BTreeSet<String>) -> Vec<Row> {
    // A unit is a session with its matching tabs, or a project; units are
    // ranked by their best score, ties keeping the sectioned order.
    let mut units: Vec<(i32, Vec<Row>)> = Vec::new();

    for session in running(snapshot).into_iter().chain(saved(snapshot)) {
        let by_name = fuzzy::score(query, &session.name);
        let unfolded = expanded.contains(&session.name);
        // A tab matches by its own name, or by "session/tab" when the
        // session name alone does not (so "acm" does not list every tab of
        // acme, but "acm cer" finds cerberus).
        let tabs: Vec<(i32, &TabEntry)> = session
            .tabs
            .iter()
            .filter_map(|tab| {
                let own = fuzzy::score(query, &tab.name);
                let joined = if by_name.is_none() {
                    fuzzy::score(query, &format!("{}/{}", session.name, tab.name))
                } else {
                    None
                };
                own.into_iter().chain(joined).max().map(|score| (score, tab))
            })
            .collect();

        let best = by_name.into_iter().chain(tabs.iter().map(|(score, _)| *score)).max();
        let Some(best) = best else { continue };

        let mut rows = vec![session_row(session, unfolded || !tabs.is_empty())];
        if unfolded {
            rows.extend(session.tabs.iter().map(|tab| tab_row(session, tab)));
        } else {
            rows.extend(tabs.iter().map(|(_, tab)| tab_row(session, tab)));
        }
        units.push((best, rows));
    }

    for project in open_projects(snapshot) {
        let RowKind::Project { rel, .. } = &project.kind else { continue };
        if let Some(score) = fuzzy::score(query, rel) {
            units.push((score, vec![project]));
        }
    }

    units.sort_by_key(|unit| std::cmp::Reverse(unit.0)); // stable: ties keep their order
    let mut rows: Vec<Row> = units.into_iter().flat_map(|(_, rows)| rows).collect();

    // Offer to create a session named after the filter, unless one exists.
    let name = target::session_name(query.trim());
    if !target::looks_like_path(query) && !snapshot.sessions.iter().any(|s| s.name == name) {
        rows.push(Row::plain(RowKind::Create { name }));
    }
    rows
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub fn tab(id: usize, name: &str) -> TabEntry {
        TabEntry { id, position: id, name: name.to_owned(), attention: 0, working: false }
    }

    pub fn session(name: &str, tabs: &[&str], last_used: u64) -> SessionEntry {
        SessionEntry {
            name: name.to_owned(),
            running: true,
            current: false,
            tabs: tabs.iter().enumerate().map(|(i, t)| tab(i, t)).collect(),
            last_used,
            saved_secs_ago: 0,
        }
    }

    pub fn saved_session(name: &str, secs_ago: u64) -> SessionEntry {
        SessionEntry { running: false, saved_secs_ago: secs_ago, ..session(name, &[], 0) }
    }

    pub fn project(rel: &str) -> ProjectEntry {
        ProjectEntry { rel: rel.to_owned(), dir: format!("C:/Projects/{rel}") }
    }

    /// acme (current, 2 tabs), globex (previous), two saved sessions
    /// (one stale) and four projects, one of them already open as a tab.
    pub fn sample() -> Snapshot {
        Snapshot {
            sessions: vec![
                session("globex", &["globex-time"], 50),
                SessionEntry { current: true, ..session("acme", &["cerberus", "tools"], 99) },
                saved_session("initech", 3600),
                saved_session("old-client", STALE_AFTER_SECS + 1),
            ],
            projects: vec![
                project("acme/cerberus"),
                project("acme/api-agent"),
                project("initech/IDE"),
                project("sentinel"),
            ],
        }
    }

    fn labels(rows: &[Row]) -> Vec<String> {
        rows.iter()
            .map(|row| match &row.kind {
                RowKind::Header(title) => format!("# {title}"),
                RowKind::Session { name, .. } => name.clone(),
                RowKind::Tab { name, .. } => format!("  {name}"),
                RowKind::Project { rel, .. } => format!("· {rel}"),
                RowKind::Create { name } => format!("+ {name}"),
            })
            .collect()
    }

    #[test]
    fn an_empty_filter_shows_sections_in_order() {
        let rows = build_rows(&sample(), "", &BTreeSet::new());
        assert_eq!(
            labels(&rows),
            [
                "# Running",
                "acme", // current first
                "globex",
                "# Saved",
                "initech",
                "old-client", // stale last
                "# Projects",
                "· acme/api-agent", // cerberus is open as a tab, so left out
                "· initech/IDE",
                "· sentinel",
            ]
        );
    }

    #[test]
    fn empty_sections_have_no_header() {
        let snapshot = Snapshot { sessions: vec![session("a", &["x"], 1)], projects: vec![] };
        assert_eq!(labels(&build_rows(&snapshot, "", &BTreeSet::new())), ["# Running", "a"]);
    }

    #[test]
    fn expanded_sessions_list_their_tabs() {
        let expanded = BTreeSet::from(["acme".to_owned()]);
        let rows = build_rows(&sample(), "", &expanded);
        assert_eq!(labels(&rows)[1..4], ["acme", "  cerberus", "  tools"]);
    }

    #[test]
    fn stale_and_current_are_marked() {
        let rows = build_rows(&sample(), "", &BTreeSet::new());
        let find = |wanted: &str| {
            rows.iter().find(|r| matches!(&r.kind, RowKind::Session { name, .. } if name == wanted)).unwrap().kind.clone()
        };
        assert!(matches!(find("acme"), RowKind::Session { current: true, running: true, .. }));
        assert!(matches!(find("initech"), RowKind::Session { stale: false, running: false, .. }));
        assert!(matches!(find("old-client"), RowKind::Session { stale: true, .. }));
    }

    #[test]
    fn a_filter_ranks_across_kinds_and_offers_to_create() {
        let rows = build_rows(&sample(), "sen", &BTreeSet::new());
        assert_eq!(labels(&rows), ["· sentinel", "+ sen"]);
    }

    #[test]
    fn a_strong_project_match_beats_a_weak_session_match() {
        // "ide" is a whole segment of the project and scattered in the session.
        let snapshot = Snapshot {
            sessions: vec![session("client-deluxe", &["web"], 1)],
            projects: vec![project("initech/IDE")],
        };
        let rows = build_rows(&snapshot, "ide", &BTreeSet::new());
        assert_eq!(labels(&rows)[..2], ["· initech/IDE", "client-deluxe"]);
    }

    #[test]
    fn sessions_whose_tabs_match_expand_to_those_tabs() {
        let rows = build_rows(&sample(), "cer", &BTreeSet::new());
        assert_eq!(labels(&rows), ["acme", "  cerberus", "+ cer"]);
        assert!(matches!(rows[0].kind, RowKind::Session { expanded: true, .. }));
    }

    #[test]
    fn a_session_name_match_does_not_list_all_its_tabs() {
        let rows = build_rows(&sample(), "acm", &BTreeSet::new());
        assert_eq!(labels(&rows), ["acme", "· acme/api-agent", "+ acm"]);
    }

    #[test]
    fn session_and_tab_terms_combine() {
        let rows = build_rows(&sample(), "acm too", &BTreeSet::new());
        assert_eq!(labels(&rows)[..2], ["acme", "  tools"]);
    }

    #[test]
    fn no_create_row_for_an_existing_session_or_a_path() {
        assert!(!labels(&build_rows(&sample(), "globex", &BTreeSet::new())).contains(&"+ globex".to_owned()));
        let rows = build_rows(&sample(), "C:/tmp/x", &BTreeSet::new());
        assert!(rows.iter().all(|r| !matches!(r.kind, RowKind::Create { .. })));
    }

    #[test]
    fn the_create_row_is_always_last() {
        let rows = build_rows(&sample(), "a", &BTreeSet::new());
        assert!(matches!(rows.last().unwrap().kind, RowKind::Create { .. }));
        assert_eq!(rows.iter().filter(|r| matches!(r.kind, RowKind::Create { .. })).count(), 1);
    }

    #[test]
    fn plans_name_the_mechanism() {
        let rows = build_rows(&sample(), "", &BTreeSet::from(["acme".to_owned(), "globex".to_owned()]));
        let hint = |label: &str| {
            let index = labels(&rows).iter().position(|l| l == label).unwrap();
            plan_for(&rows[index]).unwrap().hint()
        };
        assert_eq!(hint("acme"), "stay here");
        assert_eq!(hint("  cerberus"), "go to tab cerberus");
        assert_eq!(hint("globex"), "attach globex");
        assert_eq!(hint("  globex-time"), "attach globex, tab globex-time");
        assert_eq!(hint("initech"), "resurrect initech");
        assert_eq!(hint("· acme/api-agent"), "new tab in acme");
        assert_eq!(hint("· initech/IDE"), "resurrect initech, new tab IDE");
        assert_eq!(hint("· sentinel"), "new session \"sentinel\"");
        assert!(plan_for(&rows[0]).is_none(), "headers do not open");
    }

    #[test]
    fn only_running_sessions_with_tabs_are_not_leaves() {
        let rows = build_rows(&sample(), "", &BTreeSet::new());
        let leaf = |label: &str| rows[labels(&rows).iter().position(|l| l == label).unwrap()].is_leaf();
        assert!(!leaf("acme"));
        assert!(leaf("initech"));
        assert!(leaf("· sentinel"));
    }

    #[test]
    fn attention_rolls_up_from_tabs_to_the_session() {
        let mut snapshot = sample();
        snapshot.sessions[1].tabs[1].attention = 2;
        snapshot.sessions[1].tabs[0].working = true;
        let rows = build_rows(&snapshot, "", &BTreeSet::from(["acme".to_owned()]));
        assert_eq!((rows[1].attention, rows[1].working), (2, true));
        assert_eq!((rows[2].attention, rows[2].working), (0, true));
        assert_eq!((rows[3].attention, rows[3].working), (2, false));
    }
}
