#!/usr/bin/env bash
# Start a slot's tool the first time its window is shown, for tmux.
#
#   lazy-slot.sh SESSION INDEX
#
# Run in the background by tmux.conf's session-window-changed hook, with the
# window the hook fired for: switching quickly queues one job per window, and
# by the time they run the client is on the last one. slot_start
# (mux-lib.sh) does the work, and nothing for a window not waiting to start.
# psmux starts its slots from the keys instead (psmux.conf).
set -u
# shellcheck source=mux-lib.sh
source "${BASH_SOURCE[0]%[\\/]*}/mux-lib.sh"

[[ -n "${1:-}" && -n "${2:-}" ]] && slot_start "$1" "$2"
exit 0
