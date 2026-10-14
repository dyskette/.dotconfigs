# Detect terminal background color via OSC 11 and return "dark" or "light".
# Works with modern terminals (Windows Terminal, GNOME Terminal, Ghostty, etc.)
function detect_terminal_theme() {
	[[ -e /dev/tty ]] || return 1

	local fd response
	exec {fd}<>/dev/tty

	# Read up to the BEL that ends the reply rather than a fixed byte count
	# under a 100ms window: terminals that answer late (Zed, while it starts)
	# otherwise leave the reply in the input queue, where readline prints it
	# at the first prompt. -s turns echo off, -d puts the tty in cbreak.
	printf '\033]11;?\007' >&"$fd"
	IFS= read -rs -d $'\a' -t 0.5 -u "$fd" response
	exec {fd}>&-

	[[ -z "$response" ]] && return 1

	# Terminals that end the reply with ST instead of BEL hit the timeout;
	# the partial read still holds the colour.
	response="${response%%$'\033\\'*}"

	# Extract rgb:R/G/B from OSC 11 response
	[[ "$response" =~ $'\033']11\;rgba?:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+) ]] || return 1

	# Scale channels to [0,1], apply sRGB gamma, compute CIELAB perceived lightness
	awk -v rh="${BASH_REMATCH[1]}" -v gh="${BASH_REMATCH[2]}" -v bh="${BASH_REMATCH[3]}" 'BEGIN {
		# Scale hex to [0,1]: value / (16^len - 1)
		n = length(rh); r = strtonum("0x" rh) / (16^n - 1)
		n = length(gh); g = strtonum("0x" gh) / (16^n - 1)
		n = length(bh); b = strtonum("0x" bh) / (16^n - 1)

		# sRGB linearize
		r = (r <= 0.04045) ? r / 12.92 : ((r + 0.055) / 1.055) ^ 2.4
		g = (g <= 0.04045) ? g / 12.92 : ((g + 0.055) / 1.055) ^ 2.4
		b = (b <= 0.04045) ? b / 12.92 : ((b + 0.055) / 1.055) ^ 2.4

		# CIE luminance -> CIELAB L* [0,1]
		Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
		L = (Y <= 216/24389) ? Y * 24389/27/100 : (Y^(1/3) * 116 - 16) / 100

		print (L < 0.5) ? "dark" : "light"
	}'
}

function apply_theme() {
	local theme="$1"
	if [[ "$theme" == "light" ]]; then
		export BAT_THEME='rose-pine-dawn'
	else
		export BAT_THEME='gruvbox'
	fi
	export SYSTEM_COLOR_THEME="$theme"
}

# Set the pane title to the command being run
function set_command_title() {
	[[ $- != *i* ]] && return

	case "$BASH_COMMAND" in
		__*)                   return ;;
		"$PROMPT_COMMAND")     return ;;
		"trap - DEBUG")        return ;;
		printf*\\e]*)          return ;;
	esac

	local first_word=${BASH_COMMAND%% *}
	printf "\033]2;%s\007" "$first_word" >/dev/tty
}

# At the prompt the title is the current folder (~ for home), so a tab or
# tmux window reads as where the shell is rather than which shell it is.
function reset_title() {
	[[ $- != *i* ]] && return
	local dir="${PWD/#$HOME/\~}"
	dir="${dir##*/}"
	printf "\033]2;%s\007" "${dir:-/}" >/dev/tty
}

# History: append to the file after every command so concurrent shells and
# abrupt exits don't lose commands. `histappend` prevents the on-exit write
# from clobbering entries written by other shells.
shopt -s histappend
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T  '

# The prompt: [󰣀 ][domain\]user@host dir ❯
#
# Plain bash only, no command substitution or external program: a fork is
# what makes a prompt slow, and Git Bash's fork is especially expensive. Who
# and where never change within a shell, so that part is built once; only the
# status colour is set before each prompt. Colours are the terminal's own 16,
# so they follow its light/dark theme by themselves.
function __prompt_init() {
	local user="${USER:-$USERNAME}" host="${HOSTNAME%%.*}"
	local domain="" ssh="" user_style='\[\e[32m\]' char='❯'

	# Domain accounts (AD, Entra ID) are domain\user, as whoami prints them,
	# and that is the name runas, ACLs and shares want. A local Windows
	# account's domain is the machine itself, so it is left out there.
	if [[ -n "$USERDOMAIN" && "${USERDOMAIN,,}" != "${COMPUTERNAME,,}" ]]; then
		domain="\[\e[2m\]${USERDOMAIN,,}\\\\\[\e[22m\]"
	fi

	# root, or an elevated Windows shell: only an elevated token carries the
	# Administrators group (544).
	if (( EUID == 0 )) || [[ " ${GROUPS[*]} " == *" 544 "* ]]; then
		user_style='\[\e[1;31m\]'
		char='#'
	fi

	if [[ -n "$SSH_CONNECTION" || -n "$SSH_TTY" ]]; then
		ssh='\[\e[33m\]󰣀\[\e[0m\] '
	fi

	__prompt_head="${ssh}${domain}${user_style}${user}\[\e[0m\]\[\e[34m\]@${host,,}\[\e[0m\] \[\e[36m\]\w\[\e[0m\] "
	__prompt_char="$char"
}

function __prompt_command() {
	# First, before anything overwrites $?.
	local status=$?
	history -a
	reset_title

	local style='\[\e[32m\]'
	(( status )) && style='\[\e[31m\]'
	PS1="${__prompt_head}${style}${__prompt_char}\[\e[0m\] "
}

if [[ $- == *i* ]]; then
	trap 'set_command_title' DEBUG

	# \w keeps only the last three folders: ~/.../a/b/c
	PROMPT_DIRTRIM=3
	__prompt_init
	PROMPT_COMMAND=__prompt_command

	# Detect theme once at startup
	if [[ -n "$TMUX" ]]; then
		_theme=$(tmux show-environment -g SYSTEM_COLOR_THEME 2>/dev/null | cut -d= -f2)
	else
		_theme=$(detect_terminal_theme)
	fi

	apply_theme "${_theme:-dark}"
	unset _theme

	# Emit OSC 9;9 so Windows Terminal can track CWD for duplicate tab/pane
	if [[ -n "$WT_SESSION" ]] && command -v wslpath &>/dev/null; then
		PROMPT_COMMAND=${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"'
	fi
fi
