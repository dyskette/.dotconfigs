# Detect terminal background color via OSC 11 and return "dark" or "light".
# Works with modern terminals (Windows Terminal, GNOME Terminal, Ghostty, etc.)
function detect_terminal_theme() {
	[[ -e /dev/tty ]] || return 1

	local old_stty fd response
	old_stty=$(stty -g -F /dev/tty 2>/dev/null) || return 1

	exec {fd}<>/dev/tty
	stty -F /dev/tty raw -echo min 0 time 1 2>/dev/null || { exec {fd}>&-; return 1; }

	printf '\033]11;?\007' >&"$fd"
	response=$(dd bs=1 count=64 <&"$fd" 2>/dev/null)

	stty -F /dev/tty "$old_stty" 2>/dev/null
	exec {fd}>&-

	[[ -z "$response" ]] && return 1

	# Strip BEL / ST terminators
	response="${response%%$'\007'*}"
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
		starship config palette rose-pine-dawn
		export BAT_THEME='rose-pine-dawn'
	else
		starship config palette adwaita
		export BAT_THEME='adwaita'
	fi
	export SYSTEM_COLOR_THEME="$theme"
}

# Set the pane title to the command being run
function set_command_title() {
	[[ $- != *i* ]] && return

	case "$BASH_COMMAND" in
		*"starship_precmd"*)   return ;;
		*"__bp_trap_string"*)  return ;;
		"$PROMPT_COMMAND")     return ;;
		"trap - DEBUG")        return ;;
		printf*\\e]*)          return ;;
	esac

	local first_word=${BASH_COMMAND%% *}
	printf "\033]2;%s\007" "$first_word" >/dev/tty
}

function reset_title() {
	[[ $- != *i* ]] && return
	printf "\033]2;bash\007" >/dev/tty
}

if [[ $- == *i* ]]; then
	trap 'set_command_title' DEBUG
	PROMPT_COMMAND="reset_title"

	if command -v starship &>/dev/null; then
		export STARSHIP_CONFIG="$HOME/.config/starship/config.toml"
		eval "$(starship init bash)"

		# Detect theme once at startup
		if [[ -n "$TMUX" ]]; then
			_theme=$(tmux show-environment -g SYSTEM_COLOR_THEME 2>/dev/null | cut -d= -f2)
		else
			_theme=$(detect_terminal_theme)
		fi
		apply_theme "${_theme:-dark}"
		unset _theme
	fi

	# Emit OSC 9;9 so Windows Terminal can track CWD for duplicate tab/pane
	if [[ -n "$WT_SESSION" ]] && command -v wslpath &>/dev/null; then
		PROMPT_COMMAND=${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"'
	fi
fi
