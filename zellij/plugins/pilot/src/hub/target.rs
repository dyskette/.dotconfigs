//! Where a folder opens: which session (its client) and which tab (the
//! folder itself). The same rules as `zj` (powershell/Zellij.psm1,
//! Get-ZjTarget and New-ZjServiceLayout); keep the two in step.

/// A folder resolved to its session and tab.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Target {
    pub session: String,
    pub tab: String,
    pub dir: String,
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

/// The target of a project given relative to the projects root: the first
/// segment is the client (the session), the last one the service (the tab).
/// A project directly under the root is its own session with one tab.
pub fn project_target(rel: &str, dir: &str) -> Target {
    let parts = segments(rel);
    let client = parts.first().copied().unwrap_or(rel);
    let leaf = parts.last().copied().unwrap_or(rel);
    Target { session: session_name(client), tab: leaf.to_owned(), dir: dir.to_owned() }
}

/// The target of any folder: by the project rule when it is inside `root`
/// (compared without regard to case or separators), else a session of its
/// own named after the folder.
pub fn folder_target(dir: &str, root: &str) -> Target {
    let dir_parts = segments(dir);
    let root_parts = segments(root);
    let inside = dir_parts.len() > root_parts.len()
        && dir_parts.iter().zip(&root_parts).all(|(a, b)| a.eq_ignore_ascii_case(b));
    if inside {
        return project_target(&dir_parts[root_parts.len()..].join("/"), dir);
    }
    let leaf = dir_parts.last().copied().unwrap_or(dir);
    Target { session: session_name(leaf), tab: leaf.to_owned(), dir: dir.to_owned() }
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

/// The marker in layouts/service.kdl that names the tab; a layout without it
/// was changed and this code has to follow.
const TAB_ANCHOR: &str = "ui name=\"service\" focus=true";

/// The service layout for one tab, with its name and folder filled in (the
/// layout file names its tab "service" and has no cwd).
pub fn service_layout(template: &str, target: &Target) -> Result<String, String> {
    if !template.contains(TAB_ANCHOR) {
        return Err(format!("the service layout no longer contains '{TAB_ANCHOR}'"));
    }
    let tab = format!("ui name={} cwd={} focus=true", kdl_string(&target.tab), kdl_string(&target.dir));
    Ok(template.replacen(TAB_ANCHOR, &tab, 1))
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
    fn projects_map_to_client_session_and_service_tab() {
        let t = project_target("acme/cerberus", r"C:\Projects\acme\cerberus");
        assert_eq!((t.session.as_str(), t.tab.as_str()), ("acme", "cerberus"));

        let grouped = project_target(r"acme\cerberus\ORDERS_API", "d");
        assert_eq!((grouped.session.as_str(), grouped.tab.as_str()), ("acme", "ORDERS_API"));

        let solo = project_target("sentinel", "d");
        assert_eq!((solo.session.as_str(), solo.tab.as_str()), ("sentinel", "sentinel"));
    }

    #[test]
    fn folders_inside_the_root_follow_the_project_rule() {
        let t = folder_target(r"c:\projects\acme\api\", r"C:\Projects");
        assert_eq!((t.session.as_str(), t.tab.as_str()), ("acme", "api"));
    }

    #[test]
    fn folders_outside_the_root_are_their_own_session() {
        let t = folder_target(r"D:\work\.tool", r"C:\Projects");
        assert_eq!((t.session.as_str(), t.tab.as_str()), ("tool", ".tool"));

        // A sibling sharing the root's prefix is not inside it.
        let sibling = folder_target(r"C:\ProjectsOld\acme\api", r"C:\Projects");
        assert_eq!(sibling.session, "api");

        // The root itself is not a project of itself.
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
    fn the_layout_gets_the_tab_name_and_folder() {
        let template = "layout {\n    ui name=\"service\" focus=true {\n    }\n}";
        let target = Target { session: "acme".into(), tab: "api \"v2\"".into(), dir: r"C:\Projects\acme\api".into() };
        let layout = service_layout(template, &target).unwrap();
        assert!(layout.contains(r#"ui name="api \"v2\"" cwd="C:\\Projects\\acme\\api" focus=true"#));
        assert!(service_layout("layout { }", &target).is_err());
    }
}
