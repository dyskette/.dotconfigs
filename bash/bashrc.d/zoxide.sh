# zoxide: `z foo` jumps to the most frecent folder matching foo, `zi` picks
# one with fzf. yazi's `z` key reads the same database. Loaded after
# prompt.sh (alphabetical order), since its hook appends to PROMPT_COMMAND.
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init bash)"
fi
