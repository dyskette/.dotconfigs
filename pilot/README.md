# pilot

A Zellij plugin, in Rust, compiled to WebAssembly. It drove the workspace
Zellij used to run here: one session per repo, one tab per activity, Alt+hjkl
crossing between Neovim windows and Zellij panes, and a hub listing running
sessions, saved sessions and projects in one fuzzy-filtered list.

**Nothing loads it today.** `zellij/config.kdl` was reset to the stock modes
and the Everforest theme, and the shell commands that went with the plugin
(`zj`, `zja`, `zjr`, `zj-hub-projects`, `powershell/Zellij.psm1`) are gone —
`git log -- zellij/` has them if they are wanted back. The crate is kept here
because the work in it is worth more than the workspace it was built for.

## Layout

| Path | What it is |
| --- | --- |
| `src/main.rs` | The plugin: nav, resize, activity tabs, lobby sweeping, the permission list |
| `src/hub/` | The session hub: model, fuzzy matcher, targets, scheduling, rendering |
| `build-pilot.sh`, `Build-Pilot.ps1` | Build to `pilot.wasm` and cache Zellij's permission grant. Twins; keep them in step |
| `tools/` | Manual end-to-end helpers: type keys into, and read the screen of, a test window without focus |
| `research/` | Clones of upstream session managers (sesh, tmux-sessionizer and friends), read while deciding what replaces this. Not tracked |

`pilot.wasm` and `target/` are build output and are not committed.

## Building

```sh
./build-pilot.sh          # or ./build-pilot.sh --test to run the unit tests first
```

Needs `cargo` and `rustup`; the `wasm32-wasip1` target is added if missing.

## Using it again

Point a Zellij config at the built file and load it at session start:

```kdl
plugins {
    pilot location="file:~/.dotconfigs/pilot/pilot.wasm"
}
load_plugins {
    pilot
}
```

That is the path the build scripts grant permissions for, so the plugin comes
up without a prompt in sessions started with `zellij attach -b`. The keys that
drove it, and the `agent_command` / `projects_command` settings the hub reads,
are in the history of `zellij/config.kdl`.
