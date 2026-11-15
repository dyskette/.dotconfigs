# 1. The workspace model: sessions, tabs and keys

Status: Accepted, not implemented. 2026-11-15.

Supersedes the model described in `../README.md`, which still documents the
old one until this is built.

## Context

The workspace as built reads `session = client`, `tab = service`, where a
service tab holds an editor, an agent and a stack of dev, test and shell
panes. That shape was never arrived at from friction: it was generated whole,
it sounded reasonable and then it had to be lived in. The parts of the config
that get used and liked (the hub, `Alt h/j/k/l` across Neovim and Zellij) were
the parts that answered a real annoyance. The rest accumulated.

Watching how the days actually go contradicts the model on almost every point:

- **Time splits roughly half agent, a quarter editor, a quarter shell.** The
  agent is the single biggest consumer of attention, and the layout treats it
  as a side pane.
- **Shells are ephemeral.** Spawn one, do a thing, quit. They are not a pane
  to be laid out.
- **Long-running services run under Aspire**, behind a web UI, outside the
  terminal. The dev/test stack exists to hold processes that are not there.
  It is a layout built for a workflow nobody has.
- **Switching repos is the dominant action**, not arranging panes inside one:
  work in one repo, run to another to fix something, move to a third to plan
  a feature. Often across clients, not within one.
- **Worktrees were tried and abandoned.** Legacy projects need config that the
  repo will not accept, Aspire wiring, and orchestration scripts that live
  outside the tree, so a second checkout means rewiring paths for every tool.
  Stashing and doing one thing at a time wins.
- **Restarts matter** (a machine stops responding between calls) but picking
  what to resume by hand has been fine for years.

The input model has its own problem. After `Alt g`, some keys perform an
action (`g` lazygit, `y` yazi) and others enter a mode (`p` pane, `t` tab,
`r` resize). One gesture, two meanings, so it never becomes muscle memory.

## Decision

**A session is a repo.** Flat, long-lived, one per repo. Branch and ticket
work happens inside lazygit and the editor, not by creating sessions. The hub
switches between them, which makes the hub the primary interface of the
workspace rather than a convenience.

**A second kind of session is the umbrella**: rooted at the parent of several
repos, agent-first, usually with no editor, for the cross-repo questions that
otherwise mean a VSCode multi-root workspace. It is created by pointing the
hub at a folder and choosing it as an umbrella. Its value is that the agent's
conversation accumulates there and gets returned to, so it must never be swept
as unused.

**A tab is one full-screen activity**, created on demand: editor, agent,
lazygit. Nothing is pre-arranged and nothing auto-starts. A session opens as
one tab with Neovim in it. Full screen because reading code and reading agent
output are different jobs and neither wants half a screen.

```
session = repo            orders-api
  tab = activity            editor │ agent │ lazygit
    ┌──────────────── one activity, full screen ─────────────┐
    │ nvim                                                   │
    │                                                        │
    │   Alt h/j/k/l moves inside it, and crosses into the    │
    │   next tab at the edge: Alt l from the rightmost       │
    │   window lands on the agent                            │
    │                                                        │
    │   floats (Alt t, Alt n) hold ephemeral shells          │
    └────────────────────────────────────────────────────────┘
```

**Floats hold everything ephemeral.** Scratch shells are summoned and
dismissed, never laid out.

**No prefix and no modes**, with one exception. Every binding is an `Alt` key
in a single shared block, so Zellij stays permanently locked and there is no
mode to be in or to leave. The exception is `Alt r`, a sticky resize mode that
repeats on `hjkl` and leaves on `Esc`, kept because quick repeated resizing
during a presentation is worth one mode.

| | |
| --- | --- |
| `Alt h/j/k/l` | Move; cross into the neighbouring tab at the edge |
| `Alt H/J/K/L` | Nudge a divider |
| `Alt r` | Sticky resize mode (`Esc` leaves), the only mode |
| `Alt e` / `Alt a` / `Alt g` | The editor, agent or lazygit tab, created if missing |
| `Alt t` | Raise or dismiss the float layer |
| `Alt n` | A new scratch shell float |
| `Alt s` | The hub |
| `Alt d` | Detach |

**One editor per session**, not per tab, because lazygit now lives in its own
tab and its `e` has to reach the editor across tabs.

**The agent starts on demand.** Often a question is a grep away and no agent
is wanted at all.

**The hub** keeps its three states (running, saved, never opened), orders by
recency so that a restart shows what was running before it, and gains a typed
path as a row, so a repo outside the projects folder no longer needs a
throwaway tab to reach. Cloning still needs a shell; that part is irreducible.

## Consequences

Neovim's own yazi (`<leader>e`) becomes the only yazi. It already opens at the
current file, already shows diagnostics pushed from Neovim and already opens
files in process, which is everything the Zellij float was being pushed
towards. The `Alt g y` float is removed, and with it commits `670576f` and
`fc7293b`, which optimised it the day before this was written.

Finding the tab's editor costs a `zellij action list-panes` call today, to
work out which panes share a tab. One editor per session removes the question
and the process with it.

What survives: pilot's Neovim-aware navigation, the hub and its model and
ranking, flatten.nvim, the float layer.

What shrinks: the editor registry loses a dimension, and the keybindings
collapse into one shared block with no modes.

What dies: the layouts, the service tab, the `Alt g` unlock and every mode
binding, the dev/test/shell stack.

Lobby sweeping and the Enter-key session marking in pilot **stay**. They look
like part of the old model but they are workarounds for Zellij itself, which
kills sessions nobody pressed Enter in and leaves abandoned lobbies behind.
Only the ambition of restoring everything automatically goes, since picking by
hand is acceptable.

Costs taken on deliberately:

- **No prefix means no escape hatch.** If an `Alt` letter collides with a key
  an agent TUI wants, there is no second way to send it. `Alt a`, `Alt e` and
  `Alt g` were checked against the agents in use; a future agent may force a
  rebinding.
- **lazygit's `e` now crosses tabs**, so opening a file has to switch tabs and
  not merely focus a pane.
- **A long-running terminal process needs a deliberate split**, since no stack
  is laid out for it. This is accepted because those processes run under
  Aspire.
- **The README and both `config.kdl` files describe the old model** until this
  is implemented.

## Alternatives

**Keep `session = client`, `tab = service`.** Rejected: switching is often
across clients, so the hub is reached for anyway, and a client with dozens of
services becomes a dozen tabs to step through instead of a list to search.

**A tmux-style prefix (`Ctrl a`, `Ctrl Space`).** Rejected: once `Alt h/j/k/l`
stays unprefixed, the prefix carries only new-session, detach, rename, hub and
close, which do not justify it. `Ctrl a` in particular costs beginning-of-line
in agent prompts and shells, which is where three quarters of the time goes.

**Editor and agent side by side.** Rejected: both end up cramped on a laptop,
agent output wraps badly, and the editor is not wanted while reading that
output anyway.

**Building an umbrella by multi-selecting repos** and rooting at their common
parent. Rejected as more machinery than pointing at a folder, and umbrellas
are whole folders in practice rather than subsets.

**Bringing the Zellij yazi float to parity** with Neovim's, by pushing
diagnostics into it over DDS and hovering the current file. Rejected: it
duplicates `<leader>e`, which already does both, and there is no place left to
press `Alt g y` from once shells are floats.

**Worktrees for parallel branches.** Rejected from experience, as above.

**Going back to tmux.** Genuinely on the table: tmux is less awkward and its
config is still maintained here. What keeps Zellij is the hub, which needs a
plugin runtime with its own UI and state and would be a pile of shell scripts
and popups in tmux. The honest reading is that Zellij earns its place where it
does something tmux cannot, and loses on feel everywhere it competes with tmux
directly. This model keeps it to the former.
