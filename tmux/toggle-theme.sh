#!/usr/bin/env bash
# Toggle tmux theme between dark and light.

current=$(tmux show-environment -g SYSTEM_COLOR_THEME 2>/dev/null | cut -d= -f2)
client_tty=$(tmux display-message -p '#{client_tty}')

if [ "$current" = "light" ]; then
	~/.dotconfigs/tmux/set-theme.sh dark "$client_tty"
	tmux display-message "Theme: dark"
else
	~/.dotconfigs/tmux/set-theme.sh light "$client_tty"
	tmux display-message "Theme: light"
fi
