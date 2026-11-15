//! Where a folder opens: which session, and what that session starts on.
//! The same rules as `zj` (zellij/bin/zj-lib.sh, `zj_target` and
//! `zj_session_layout`; powershell/Zellij.psm1 on Windows); keep them in step.
//!
//! One session per repo, named after the repo's own folder however deep it
//! sits under the projects root. The client folder above it is a way of
//! filing things, not a level of the workspace
//! (zellij/decisions/0001-workspace-model.md).

/// What a new session opens on.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Kind {
    /// A repo: opens on the editor, with the agent and lazygit a key away.
    #[default]
    Repo,
    /// A folder holding several repos: opens on an agent instead, which is
    /// the whole point of one, and often never gets an editor at all.
    Umbrella,
}

impl Kind {
    /// The tab name and the command its only pane runs.
    fn activity(self) -> (&'static str, &'static str) {
        match self {
            Kind::Repo => ("editor", "nvim"),
            Kind::Umbrella => ("agent", "zja"),
        }
    }
}

/// A folder resolved to the session it opens.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Target {
    pub session: String,
    pub dir: String,
    pub kind: Kind,
}

impl Target {
    pub fn new(session: String, dir: String) -> Self {
        Target { session, dir, kind: Kind::Repo }
    }

    pub fn as_umbrella(mut self) -> Self {
        self.kind = Kind::Umbrella;
        self
    }
}

/// A Zellij session name from a folder name: anything but letters, digits,
/// `-`, `_` and `.` becomes `_`, and leading or trailing dots go.
///
/// On Windows (Zellij 0.46.0) a session named `.dotconfigs` starts and runs
/// but can never be listed, reached or resurrected, and a trailing dot breaks
/// the same way, so `~/.dotconfigs` is session `dotconfigs`.
pub fn session_name(folder: &str) -> String {
    let clean: String = folder
        .chars()
        .map(|c| if c.is_alphanumeric() || matches!(c, '_' | '-' | '.') { c } else { '_' })
        .collect();
    let clean = clean.trim_matches('.');
    if clean.is_empty() { "_".to_owned() } else { clean.to_owned() }
}

/// Path segments, whichever separator was used.
fn segments(path: &str) -> Vec<&str> {
    path.split(['/', '\\']).filter(|s| !s.is_empty()).collect()
}

/// The target of any folder: a session named after the folder itself. Where
/// it sits relative to the projects root makes no difference, which is the
/// change from the old model, where the first segment under the root became
/// the session and the folder became a tab in it.
pub fn folder_target(dir: &str, _root: &str) -> Target {
    let parts = segments(dir);
    let leaf = parts.last().copied().unwrap_or(dir);
    Target::new(session_name(leaf), dir.to_owned())
}

/// Whether text typed at the "new" prompt is a folder rather than a session
/// name: it has a separator, or starts with `~`, `.` or a drive letter.
pub fn looks_like_path(text: &str) -> bool {
    let text = text.trim();
    let drive = {
        let mut chars = text.chars();
        matches!((chars.next(), chars.next()), (Some(c), Some(':')) if c.is_ascii_alphabetic())
    };
    drive || text.contains(['/', '\\']) || text.starts_with(['~', '.'])
}

/// Quote a string for a KDL document.
pub fn kdl_string(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

/// The layout a new session opens with: one tab holding one activity, full
/// screen, in the session's folder.
///
/// Built here rather than patched into a layout file. The old service layout
/// had five panes and three swap arrangements, and had to be found on disk
/// and have an anchor substituted into it; one pane is shorter written out,
/// and there is no file to fall out of step with.
pub fn session_layout(target: &Target) -> String {
    let (name, command) = target.kind.activity();
    // Neovim's statusline already says what it is, so the editor's title row
    // goes to code. The agent keeps its row, which carries inbox markers.
    let borderless = matches!(target.kind, Kind::Repo);
    format!(
        r#"layout {{
    // The same one-line bar as the built-in compact layout.
    tab_template name="ui" {{
        children
        pane size=1 borderless=true {{
            plugin location="compact-bar"
        }}
    }}

    ui name={name} cwd={dir} focus=true {{
        pane name={name} command={command} borderless={borderless}
    }}
}}
"#,
        name = kdl_string(name),
        command = kdl_string(command),
        dir = kdl_string(&target.dir),
        borderless = borderless,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_names_are_safe_for_zellij() {
        assert_eq!(session_name("acme"), "acme");
        assert_eq!(session_name("my client"), "my_client");
        assert_eq!(session_name("app.v2"), "app.v2");
        assert_eq!(session_name(".dotconfigs"), "dotconfigs");
        assert_eq!(session_name("..hidden.."), "hidden");
        assert_eq!(session_name("..."), "_");
    }

    #[test]
    fn a_repo_is_named_after_itself_not_its_client() {
        // The old model made this session "acme", tab "cerberus".
        let t = folder_target(r"C:\Projects\acme\cerberus", r"C:\Projects");
        assert_eq!(t.session, "cerberus");

        let grouped = folder_target(r"C:\Projects\acme\cerberus\ORDERS_API", r"C:\Projects");
        assert_eq!(grouped.session, "ORDERS_API");

        let solo = folder_target(r"C:\Projects\sentinel", r"C:\Projects");
        assert_eq!(solo.session, "sentinel");
    }

    #[test]
    fn where_a_folder_sits_makes_no_difference() {
        assert_eq!(folder_target(r"c:\projects\acme\api\", r"C:\Projects").session, "api");
        assert_eq!(folder_target(r"D:\work\.tool", r"C:\Projects").session, "tool");
        assert_eq!(folder_target(r"C:\ProjectsOld\acme\api", r"C:\Projects").session, "api");
        assert_eq!(folder_target(r"C:\Projects", r"C:\Projects").session, "Projects");
    }

    #[test]
    fn paths_are_told_from_names() {
        for path in [r"C:\work", "~/x", "./here", "a/b", r"a\b", ".dotconfigs"] {
            assert!(looks_like_path(path), "{path} is a path");
        }
        for name in ["scratch", "client-x", "notes2"] {
            assert!(!looks_like_path(name), "{name} is a name");
        }
    }

    #[test]
    fn a_repo_opens_on_an_editor_and_an_umbrella_on_an_agent() {
        let repo = Target::new("api".into(), r"C:\Projects\acme\api".into());
        let layout = session_layout(&repo);
        assert!(layout.contains(r#"ui name="editor" cwd="C:\\Projects\\acme\\api" focus=true"#));
        assert!(layout.contains(r#"pane name="editor" command="nvim" borderless=true"#));

        let umbrella = Target::new("acme".into(), "/home/me/acme".into()).as_umbrella();
        let layout = session_layout(&umbrella);
        assert!(layout.contains(r#"ui name="agent" cwd="/home/me/acme" focus=true"#));
        assert!(layout.contains(r#"pane name="agent" command="zja" borderless=false"#));
    }

    #[test]
    fn folders_with_quotes_are_escaped_into_the_layout() {
        let odd = Target::new("x".into(), r#"/tmp/a"b"#.into());
        assert!(session_layout(&odd).contains(r#"cwd="/tmp/a\"b""#));
    }
}
