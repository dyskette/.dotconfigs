#!/usr/bin/env bash
# Start a slot's tool the first time its window is shown.
#
#   lazy-slot.sh [SESSION|-] [WINDOW]
#
# SESSION defaults to the one this runs for (psmux names it to its jobs in
# PSMUX_TARGET_SESSION); WINDOW is an id (@3) or an index (3), and defaults
# to the session's current window. slot_start (mux-lib.sh) does the work,
# only for a window still in @slots_pending, so running this twice for one
# window, or for a window with nothing to start, does nothing.
#
# Who runs it:
#   tmux   the session-window-changed hook (tmux.conf), with the window the
#          hook fired for: switching quickly queues one job per window, and
#          by the time they run the client is on the last one.
#   psmux  the slot keys, prefix 1..5 (psmux.conf), with the index. psmux
#          3.4.0 stops spawning run-shell from hooks once any program has run
#          in the session, while commands sent by a key still run.
set -u
# shellcheck source=mux-lib.sh
source "${BASH_SOURCE[0]%[\\/]*}/mux-lib.sh"

s="${1:--}"
w="${2:-}"
if [[ "$s" == - ]]; then
    current_session
    s="$REPLY"
fi
[[ -n "$s" ]] || exit 0
# An index, or nothing: the window's id, which slot_start tracks.
if [[ ! "$w" =~ ^@ ]]; then
    w="$("$mux" display-message -t "=$s:$w" -p '#{window_id}' 2>/dev/null)"
fi
[[ -n "$w" ]] && slot_start "$s" "$w"
exit 0
