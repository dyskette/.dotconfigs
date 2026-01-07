#!/bin/bash

# Session switcher script for tmux - sorted by recency
for session in $(tmux list-sessions -F '#{?session_attached,,#{session_activity}:#{session_name}}' | sed '/^$/d' | sort -rn | cut -d: -f2); do
    count=$(tmux list-windows -t $session | wc -l)
    echo "$session ($count windows)"
done | \
fzf --reverse \
    --header jump-to-session \
    --border=none \
    --preview-window=border-left \
    --preview 'tmux list-windows -t $(echo {} | cut -d" " -f1) -F "#{?window_active,* ,  }#{window_index}: #{window_name} (#{window_panes} panes)"' | \
cut -d' ' -f1 | \
xargs tmux switch-client -t