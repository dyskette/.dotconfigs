function tmux-pwsh {
	cd "$(pwsh.exe -c 'Write-Host -NoNewline "$env:USERPROFILE"' | xargs -0 wslpath)"
	tmux -L pwsh -f "$HOME/.dotconfigs/tmux/pwsh.conf" "$@"
	cd -
}

# The session for a project, on tmux or psmux (Git Bash): `tm DIR` opens DIR's,
# `tm` alone picks one the way prefix s does (tmux/projects.conf, its roots,
# zoxide). Switches from inside a client, attaches from outside.
tm() {
	bash "$HOME/.dotconfigs/tmux/scripts/project-picker.sh" "$@"
}
