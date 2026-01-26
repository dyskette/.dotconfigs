#!/bin/bash

# Session switcher script for tmux - sorted by recency
# Colors
YELLOW="\033[33m"
BLUE="\033[34m"
GREEN="\033[32m"
CYAN="\033[36m"
RESET="\033[0m"

for session in $(tmux list-sessions -F '#{?session_attached,,#{session_activity}:#{session_name}}' | sed '/^$/d' | sort -rn | cut -d: -f2); do
    count=$(tmux list-windows -t $session | wc -l)
    echo "$session ($count windows)"
done | \
fzf --reverse \
    --header jump-to-session \
    --border=none \
    --preview-window=border-left \
    --ansi \
    --preview 'session=$(echo {} | cut -d" " -f1)
        YELLOW="\033[33m"
        BLUE="\033[34m"
        GREEN="\033[32m"
        CYAN="\033[36m"
        BOLD="\033[1m"
        RESET="\033[0m"
        ICON_SESSION="\uf490"
        ICON_WINDOW="\uf2d0"
        ICON_PANE="\uea85"
        ICON_ACTIVE="\ueacf"
        ICON_INACTIVE="\uead7"

        # Session header with icon
        printf "${YELLOW}${ICON_SESSION} ${session}${RESET}\n"

        windows=$(tmux list-windows -t "$session" -F "#{window_index}:#{window_name}:#{window_active}")
        win_count=$(echo "$windows" | wc -l)
        win_current=0

        echo "$windows" | while IFS=: read -r win_idx win_name win_active; do
            win_current=$((win_current + 1))
            if [[ $win_current -eq $win_count ]]; then
                win_prefix="└──"
                pane_prefix="    "
            else
                win_prefix="├──"
                pane_prefix="│   "
            fi

            if [[ "$win_active" == "1" ]]; then
                printf "${win_prefix} ${BOLD}${BLUE}${ICON_ACTIVE} ${ICON_WINDOW} ${win_idx}: ${win_name}${RESET}\n"
            else
                printf "${win_prefix} ${BLUE}${ICON_INACTIVE} ${ICON_WINDOW} ${win_idx}: ${win_name}${RESET}\n"
            fi

            panes=$(tmux list-panes -t "$session:$win_idx" -F "#{pane_index}:#{pane_active}:#{pane_current_command}:#{pane_current_path}")
            pane_count=$(echo "$panes" | wc -l)
            pane_current=0

            echo "$panes" | while IFS=: read -r pane_idx pane_active pane_cmd pane_path; do
                pane_current=$((pane_current + 1))
                dir=$(basename "$pane_path")
                if [[ $pane_current -eq $pane_count ]]; then
                    pane_conn="└──"
                else
                    pane_conn="├──"
                fi

                if [[ "$pane_active" == "1" ]]; then
                    printf "${pane_prefix}${pane_conn} ${BOLD}${GREEN}${ICON_ACTIVE} ${ICON_PANE} ${pane_idx}: ${pane_cmd}${RESET} ${CYAN}(${dir})${RESET}\n"
                else
                    printf "${pane_prefix}${pane_conn} ${GREEN}${ICON_INACTIVE} ${ICON_PANE} ${pane_idx}: ${pane_cmd}${RESET} ${CYAN}(${dir})${RESET}\n"
                fi
            done
        done' | \
cut -d' ' -f1 | \
xargs tmux switch-client -t
