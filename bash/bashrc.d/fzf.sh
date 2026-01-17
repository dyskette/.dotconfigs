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
  
  # Bind Ctrl+R to fzf history search
  bind -x '"\C-r": __fzf_history__'
fi
