# Set the pane title to the command being run, and mark where it starts for
# shell integration (OSC 133 C). One C per prompt line: the trap fires for
# every simple command, so the mark waits for the next prompt (D below).
function set_command_title() {
	[[ $- != *i* ]] && return

	case "$BASH_COMMAND" in
		__*)                   return ;;
		"$PROMPT_COMMAND")     return ;;
		"trap - DEBUG")        return ;;
		printf*\\e]*)          return ;;
	esac

	local first_word=${BASH_COMMAND%% *}
	if ((__command_running)); then
		printf "\033]2;%s\007" "$first_word" >/dev/tty
	else
		__command_running=1
		printf "\033]2;%s\007\033]133;C\007" "$first_word" >/dev/tty
	fi
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

# Percent-encode $PWD for the OSC 7 URI into __osc7_path. A variable rather
# than output, as command substitution would fork on every prompt; LC_ALL=C
# makes the loop walk bytes, so UTF-8 folder names (Música) are encoded byte
# by byte as the URI wants.
function __osc7_encode() {
	local path=$1 char index
	local LC_ALL=C

	__osc7_path=''
	for (( index = 0; index < ${#path}; index++ )); do
		char=${path:index:1}
		case "$char" in
			[-/:_.~a-zA-Z0-9]) __osc7_path+=$char ;;
			*) printf -v char '%%%02X' "'$char"; __osc7_path+=$char ;;
		esac
	done
}

function __prompt_command() {
	# First, before anything overwrites $?.
	local status=$?
	history -a
	reset_title

	# Shell integration (OSC 133): the end of the last command with its exit
	# code (D), then where the prompt starts (A); the prompt's end (B) is in
	# PS1 and the command start (C) in the DEBUG trap above. Zellij uses them
	# for the inbox (a long command finished or failed), for jumping between
	# prompts (Alt g s, then [ and ]) and for copying the last command's
	# output (Alt g s c). D only after a C, so the first prompt reports no
	# phantom command.
	local osc=''
	if (( __command_running )); then
		osc="\e]133;D;${status}\a"
		__command_running=0
	fi
	osc+='\e]133;A\a'

	# Report the working directory (OSC 7) so a new Zellij pane, split or tab
	# opens where this one is; Zellij forwards it to the terminal outside.
	__osc7_encode "$PWD"
	osc+="\e]7;file://${HOSTNAME}${__osc7_path}\e\\"
	# %b, never the format string itself: the encoded path carries % escapes.
	printf '%b' "$osc"

	local style='\[\e[32m\]'
	(( status )) && style='\[\e[31m\]'
	PS1="${__prompt_head}${style}${__prompt_char}\[\e[0m\] \[\e]133;B\a\]"
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
