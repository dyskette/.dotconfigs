#!/usr/bin/env bash
# Long-running tools in a popup, for tmux and psmux (run by Git Bash on
# Windows):
#
#   popup.sh lazygit|yazi
#
# Each tool runs in a detached session of its own, popup_<tool>_<session>,
# one per session the popup is opened from, started in that pane's folder.
# The popup only attaches a client to it: closing the popup (the same key
# again, bound to detach-client in popup_* sessions; see tmux.conf) leaves
# the tool running with its state, and the next popup shows it as it was.
# Quitting the tool ends its session; the next popup starts it afresh.
#
# The popup_* sessions are kept out of the project picker and the window
# switcher, and out of session_for's folder matches (mux-lib.sh).
set -u
here="${BASH_SOURCE[0]%[\\/]*}"
# shellcheck source=mux-lib.sh
source "$here/mux-lib.sh"

tool="${1:-}"
case "$tool" in
    lazygit | yazi) ;;
    *)
        printf 'usage: popup.sh lazygit|yazi\n' >&2
        exit 2
        ;;
esac

current_session
owner="$REPLY"
[[ -n "$owner" ]] || exit 1
name="popup_${tool}_${owner//[.: ]/_}"

if ! "$mux" has-session -t "=$name" 2>/dev/null; then
    # The folder of the pane the popup was opened over. Neither tmux nor
    # psmux expands formats in a popup's command, so it is asked for here.
    dir="$("$mux" display-message -t "=$owner:" -p '#{pane_current_path}' 2>/dev/null)"
    [[ -d "$dir" ]] || dir="$home"
    "$mux" new-session -d -s "$name" -c "$dir" "$tool" || exit 1
    # Only the tool in the popup. tmux.conf sets detach-on-destroy off,
    # which would move this client to another session, inside the popup,
    # when the tool quits; psmux has no such option and closes anyway.
    "$mux" set-option -t "$name" status off 2>/dev/null
    "$mux" set-option -t "$name" detach-on-destroy on 2>/dev/null
fi

# A client inside a client: tmux refuses to attach while TMUX is set.
unset TMUX TMUX_PANE
exec "$mux" attach-session -t "=$name"
