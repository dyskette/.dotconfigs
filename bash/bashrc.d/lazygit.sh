# lazygit reads every file in LG_CONFIG_FILE, later ones winning, so
# session.yml can hold the settings for lazygit's window in a tmux session:
# `e` and `o` opening files in the session's nvim (tmux/scripts/edit.sh)
# rather than in an nvim of lazygit's own. Windows sets its own list in
# powershell/CliTools.ps1, with session-windows.yml: lazygit runs these
# commands through cmd.exe there, which reaches the script through edit.cmd.
#
# The repo's own copies are named, as tmux.conf names its scripts: the
# deployed config.yml is a link to the first of them anyway.
[[ "$OSTYPE" == linux* ]] || return 0

export LG_CONFIG_FILE="$HOME/.dotconfigs/lazygit/config.yml,$HOME/.dotconfigs/lazygit/session.yml"
