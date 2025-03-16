function tmux-pwsh {
	cd "$(pwsh.exe -c 'Write-Host -NoNewline "$env:USERPROFILE"' | xargs -0 wslpath)"
	tmux -L pwsh -f "$HOME/.dotconfigs/tmux/pwsh.conf" "$@"
	cd -
}
