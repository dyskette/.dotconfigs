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

	# In a Toolbx container a login shell (toolbox enter) gets HOSTNAME from
	# /etc/profile's hostnamectl, which asks the host over the shared D-Bus,
	# while a non-login shell gets the container's own. Use the container's.
	if [[ -f /run/.toolboxenv ]]; then
		read -r host </etc/hostname
	fi

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

	# Emit OSC 9;9 so Windows Terminal can track CWD for duplicate tab/pane
	if [[ -n "$WT_SESSION" ]] && command -v wslpath &>/dev/null; then
		PROMPT_COMMAND=${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"'
	fi
fi
