#!/usr/bin/env bash
# Start a slot's tool the first time its window is shown, for tmux only
# (psmux keeps its popups; see popup.sh).
#
#   lazy-slot.sh WINDOW
#
# ensure_session (mux-lib.sh) gives every session the same windows, each a
# shell carrying the tool's command in the window option @lazy. tmux.conf
# runs this from the session-window-changed hook, so a tool starts when its
# window is first visited and never before: the numbers are the same in
# every session from the start, while a session opened to grep something
# costs five shells.
#
# The command is typed into the shell instead of replacing it, so quitting
# the tool leaves the shell -- and the window, and its number -- in place,
# the command is in history, and a wedged tool can be restarted by hand.
# @lazy is cleared before the keys are sent, so a window is only ever
# started once and this can never type into a shell that is in use.
set -u
win="${1:-}"
[[ -n "$win" ]] || exit 0

cmd="$(tmux show-options -wqv -t "$win" @lazy 2>/dev/null)"
[[ -n "$cmd" ]] || exit 0

# A pane running anything but its shell has a foreground process, which the
# keys would land in rather than at a prompt.
case "$(tmux display-message -p -t "$win" '#{pane_current_command}' 2>/dev/null)" in
    bash | sh | zsh | fish) ;;
    *) exit 0 ;;
esac

tmux set-option -wu -t "$win" @lazy 2>/dev/null
tmux send-keys -t "$win" "$cmd" Enter
