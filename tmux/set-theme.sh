#!/usr/bin/env bash
# Set tmux theme and update tty->bg via synthetic OSC 11 response.
# Usage: set-theme.sh <dark|light> [client_tty]
#
# The synthetic OSC 11 response updates tmux's tty->bg so that mode 2031
# notifications to panes (e.g. neovim) report the correct theme.

theme="$1"
client_tty="$2"

if [ "$theme" = "light" ]; then
	tmux source-file ~/.dotconfigs/tmux/rose-pine-dawn.conf
	tmux set-environment -g SYSTEM_COLOR_THEME light
	osc11_response=$'\033]11;rgb:fafa/f4f4/eded\033\\'
else
	tmux source-file ~/.dotconfigs/tmux/adwaita.conf
	tmux set-environment -g SYSTEM_COLOR_THEME dark
	osc11_response=$'\033]11;rgb:2828/2828/2828\033\\'
fi

if [ -n "$client_tty" ] && [ -w "$client_tty" ]; then
	printf '%s' "$osc11_response" > "$client_tty"
fi
