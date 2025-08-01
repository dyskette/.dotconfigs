#!/bin/bash

# Check if this session was created from a regular terminal (not attached to existing tmux)
# This happens when the session name starts with a number (default tmux naming)
current_session=$(tmux display-message -p '#S')

# Show directory selection if this looks like a new session from terminal
if [[ "$current_session" =~ ^[0-9]+$ ]]; then
    # Show directory selection popup
    selected=$(find ~ -maxdepth 3 -type d \( -name ".git" -o -name "node_modules" -o -name ".venv" \) -prune -o -type d -print 2>/dev/null | head -200 | fzf --reverse --header="select-working-directory" --preview="ls -la {}")
    
    if [ -n "$selected" ]; then
        # Create new session with selected directory and switch to it
        session_name=$(basename "$selected" | tr "." "_")
        tmux new-session -d -s "$session_name" -c "$selected"
        tmux switch-client -t "$session_name"
        
        # Kill the original numbered session
        tmux kill-session -t "$current_session"
    fi
fi