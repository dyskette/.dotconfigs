#!/bin/bash

# Create new tmux session from selected directory
selected=$(fd --type directory --max-depth 3 --exclude .git --exclude node_modules --exclude .venv --hidden . ~ | \
    sort | \
    fzf --reverse \
        --header="create-new-session" \
        --border=none \
        --preview-window=border-left \
        --preview="eza --tree --git-ignore --level 2 --colour=always --icons=always {}")

if [ -n "$selected" ]; then
    session_name=$(basename "$selected" | tr "." "_")
    tmux new-session -d -s "$session_name" -c "$selected"
    tmux switch-client -t "$session_name"
fi