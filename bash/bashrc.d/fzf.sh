# FZF history search
# Replaces default Ctrl+R with fzf-powered history search
if command -v fzf &> /dev/null; then
  __fzf_history__() {
    local selected
    selected=$(
      fc -rl 1 | \
      awk '{ cmd=$0; sub(/^[ \t]*[0-9]+[ \t]*/, "", cmd); if (!seen[cmd]++) print $0 }' | \
      fzf \
        --layout=reverse \
        --height=50% \
        --min-height=20 \
        --border=none \
        --preview-window=border-left \
        --preview 'echo {}' \
        --preview-label='Command' \
        --query="$READLINE_LINE" \
        --bind 'ctrl-y:execute-silent(echo -n {2..} | xclip -selection clipboard)+abort' \
        --header 'Press CTRL-Y to copy command, ENTER to execute' | \
      sed 's/^[ \t]*[0-9]*[ \t]*//'
    )
    
    if [ -n "$selected" ]; then
      READLINE_LINE="$selected"
      READLINE_POINT=${#READLINE_LINE}
    fi
  }
  
  # Bind Ctrl+R to fzf history search (only in interactive shells)
  [[ $- == *i* ]] && bind -x '"\C-r": __fzf_history__'

  # Zellij session manager
  # Always uses sessions — switch-session from inside, attach --create from outside
  # With no args: fzf pick from project directories
  zj() {
    local dir name

    if [[ -n "$1" ]]; then
      dir="$(realpath "$1")"
    else
      dir=$(fd --type directory --max-depth 3 --exclude .git --exclude node_modules --exclude .venv --hidden . ~ | \
        fzf --reverse --height=50% \
            --header="select project directory" \
            --border=none \
            --preview-window=border-left \
            --preview 'eza --tree --git-ignore --level 2 --colour=always --icons=always {} 2>/dev/null || ls {}')
      [[ -z "$dir" ]] && return
    fi

    name="$(basename "$dir" | tr '.' '_')"

    if [[ -n "$ZELLIJ" ]]; then
      zellij action switch-session "$name" --cwd "$dir"
    else
      zellij attach --create "$name" options --default-cwd "$dir"
    fi
  }
fi
