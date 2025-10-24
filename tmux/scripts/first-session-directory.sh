#!/bin/bash

# Check if this session was created from a regular terminal (not attached to existing tmux)
# This happens when the session name starts with a number (default tmux naming)
current_session=$(tmux display-message -p '#S')

# Show directory selection if this looks like a new session from terminal
if [[ "$current_session" =~ ^[0-9]+$ ]]; then
    # Show directory selection popup
    selected=$(fd --type directory --max-depth 3 --exclude .git --exclude node_modules --exclude .venv --hidden . ~ | \
        sort | \
        fzf --reverse \
            --header="select-working-directory" \
            --border=none \
            --preview-window=border-left \
            --preview="eza --tree --git-ignore --level 2 --colour=always --icons=always {}")

    if [ -n "$selected" ]; then
        # Create new session with selected directory and switch to it
        session_name=$(basename "$selected" | tr "." "_")
        tmux new-session -d -s "$session_name" -c "$selected"
        tmux switch-client -t "$session_name"

        # Kill the original numbered session
        tmux kill-session -t "$current_session"
    fi
fi
