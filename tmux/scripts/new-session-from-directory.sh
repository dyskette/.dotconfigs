#!/bin/bash

# Create new tmux session from selected directory
# Not sorted: sort would hold every line until fd finishes, and fzf could show
# nothing until then; unsorted, the list streams in while fd walks, and fzf
# ranks it by path once a query is typed.
selected=$(fd --type directory --max-depth 5 --exclude .git --exclude node_modules --exclude .venv --hidden . ~ | \
    fzf --reverse --scheme=path \
        --header="create-new-session" \
        --border=none \
        --preview-window=border-left \
        --preview="eza --tree --git-ignore --level 2 --colour=always --icons=always {}")

if [ -n "$selected" ]; then
    session_name=$(basename "$selected" | tr "." "_")
    tmux new-session -d -s "$session_name" -c "$selected"
    tmux switch-client -t "$session_name"
fi