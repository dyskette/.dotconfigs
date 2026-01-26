#!/bin/bash

# Interactive path builder with directory completion for new tmux session
# Uses fzf with reload to provide dynamic subdirectory suggestions

# Start from root directory by default
initial_dir="/"

# Function to list subdirectories based on current query
list_dirs() {
    local query="$1"
    
    # If query is empty, show root level directories
    if [[ -z "$query" ]]; then
        fd --type directory --max-depth 1 --exclude .git --hidden . / 2>/dev/null | sort
        return
    fi
    
    # If query ends with /, show subdirectories of that path
    if [[ "$query" == */ ]]; then
        local base_path="${query%/}"
        # Expand ~ to home directory
        base_path="${base_path/#\~/$HOME}"
        # If empty after removing /, use root
        [[ -z "$base_path" ]] && base_path='/'
        # List subdirectories
        fd --type directory --max-depth 1 --exclude .git --hidden . "$base_path" 2>/dev/null | sort
    else
        # Extract the directory part before last /
        local dir_part="${query%/*}"
        local name_part="${query##*/}"

        # If no /, search from root
        if [[ "$query" != */* ]]; then
            dir_part='/'
        else
            # Expand ~ to home directory
            dir_part="${dir_part/#\~/$HOME}"
            # Handle case where query starts with / (e.g., /tmp)
            [[ -z "$dir_part" ]] && dir_part='/'
        fi
        
        # Show directories matching the partial name
        if [[ -d "$dir_part" ]]; then
            fd --type directory --max-depth 1 --exclude .git --hidden . "$dir_part" 2>/dev/null | grep -i "$name_part" | sort
        fi
    fi
}

# Initial listing
initial_list=$(list_dirs "")

selected=$(echo "$initial_list" | fzf \
    --query="$initial_dir" \
    --prompt="Directory: " \
    --header="Type path, Ctrl+Y to select item, Enter to create session" \
    --reverse \
    --border=none \
    --bind="change:reload:
        query={q};
        base_path=\${query%/};
        base_path=\${base_path/#\~/$HOME};
        [[ -z \$base_path ]] && base_path='/';
        # If query ends with /, show subdirectories
        if [[ \$query == */ ]]; then
            fd --type directory --max-depth 1 --exclude .git --hidden . \$base_path 2>/dev/null | sort;
        else
            # Extract directory and name parts
            dir_part=\${query%/*};
            name_part=\${query##*/};
            if [[ \$query != */* ]]; then
                dir_part='/';
            else
                dir_part=\${dir_part/#\~/$HOME};
                [[ -z \$dir_part ]] && dir_part='/';
            fi;
            if [[ -d \$dir_part ]]; then
                fd --type directory --max-depth 1 --exclude .git --hidden . \$dir_part 2>/dev/null | grep -i \"\$name_part\" | sort;
            fi;
        fi
    " \
    --bind="ctrl-y:replace-query" \
    --preview="
        path={q};
        # If nothing in query, try the selected item
        [[ -z \$path ]] && path={};
        # Expand ~ to home directory
        path=\${path/#\~/$HOME};
        # Remove trailing slash for preview
        path=\${path%/};
        # If it's a directory, show its contents
        if [[ -d \$path ]]; then
            eza --tree --git-ignore --level 2 --colour=always --icons=always \$path 2>/dev/null || ls -la \$path 2>/dev/null;
        else
            # Show parent directory
            parent=\${path%/*};
            [[ -z \$parent ]] && parent='/';
            eza --tree --git-ignore --level 1 --colour=always --icons=always \$parent 2>/dev/null || ls -la \$parent 2>/dev/null;
        fi
    " \
    --preview-window=right:60%:border-left)

# If user provided a path
if [ -n "$selected" ]; then
    # Expand ~ to home directory
    selected="${selected/#\~/$HOME}"
    
    # Remove trailing slash if present
    selected="${selected%/}"
    
    # Check if directory exists
    if [ -d "$selected" ]; then
        session_name=$(basename "$selected" | tr "." "_" | tr " " "_")
        
        # Check if session already exists
        if tmux has-session -t "$session_name" 2>/dev/null; then
            tmux switch-client -t "$session_name"
        else
            tmux new-session -d -s "$session_name" -c "$selected"
            tmux switch-client -t "$session_name"
        fi
    else
        # Try to create the directory
        tmux display-message "Directory does not exist: $selected"
    fi
fi
