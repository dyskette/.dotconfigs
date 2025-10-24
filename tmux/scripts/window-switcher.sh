#!/bin/bash

# Window switcher script for tmux
tmux list-windows -F '#{session_name}:#{window_index}: #{window_name} (#{window_panes} panes) #{?window_active,[active],}' | \
fzf --reverse \
    --header jump-to-window \
    --border=none \
    --preview-window=border-left \
    --preview 'tmux list-panes -t $(echo {} | cut -d":" -f1,2) -F "#{?pane_active,* ,  }#{pane_index}: #{pane_current_command} #{pane_current_path}"' | \
cut -d':' -f1,2 | \
xargs tmux select-window -t