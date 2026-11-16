#!/usr/bin/env bash
# Start the tool of a session's current window the first time it is shown.
#
#   lazy-slot.sh SESSION
#
# Run in the background by the window-change hooks (tmux.conf, psmux.conf),
# only for a window still in the session's @slots_pending list; slot_start
# (mux-lib.sh) says what that means. The session is given rather than asked
# for: a run-shell job under psmux inherits the environment of whoever
# started the server, and psmux 3.4.0 leaves #{window_id} empty there, so the
# window is looked up here.
set -u
# shellcheck source=mux-lib.sh
source "${BASH_SOURCE[0]%[\\/]*}/mux-lib.sh"

s="${1:-}"
[[ -n "$s" ]] || exit 0
w="$("$mux" display-message -t "=$s:" -p '#{window_id}' 2>/dev/null)"
[[ -n "$w" ]] && slot_start "$s" "$w"
exit 0
