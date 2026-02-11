# Set DEBUG_THEME=1 to enable debug output
function _theme_debug() {
	[[ -n "$DEBUG_THEME" ]] && echo "[theme-debug] $*" >&2
}

# Detect terminal background color via OSC 11 query and determine light/dark.
# Implementation follows terminal-colorsaurus:
#   - Sends OSC 11 + DA1 sentinel via /dev/tty
#   - Uses BEL terminator for rxvt-unicode compatibility
#   - If DA1 arrives first, terminal doesn't support OSC 11
#   - Parses rgb:R/G/B, scales to 16-bit, computes CIELAB perceived lightness
#   - Prints "dark" or "light" to stdout; returns 1 on failure
function detect_terminal_theme() {
	# If we already determined OSC 11 is unsupported, skip the query.
	# Each shell session gets its own _OSC11_SUPPORTED variable, so
	# this won't leak across SSH sessions or into tmux.
	if [[ "$_OSC11_SUPPORTED" == "no" ]]; then
		_theme_debug "detect_terminal_theme: skipping (OSC 11 unsupported, cached)"
		return 1
	fi

	# Quirks: skip known unsupported terminals
	case "$TERM" in
		dumb|screen|screen.*|Eterm) return 1 ;;
	esac

	[[ -e /dev/tty ]] || return 1

	local old_stty fd
	old_stty=$(stty -g -F /dev/tty 2>/dev/null) || return 1

	# Open a dedicated fd to /dev/tty for reading responses
	exec {fd}<>/dev/tty

	# Raw mode: no echo, no line buffering, 1-byte reads, 1s timeout (10 deciseconds)
	stty -F /dev/tty raw -echo min 0 time 10 2>/dev/null || { exec {fd}>&-; return 1; }

	# Send OSC 11 query + DA1 sentinel.
	# Note: this only works outside tmux. Inside tmux, OSC 11 responses are
	# intercepted by tmux's input parser and never reach the pane.
	printf '\033]11;?\007\033[c' >&"$fd"

	# Read response via dd (bypasses bash read buffering, respects stty raw)
	local response
	response=$(dd bs=1 count=64 <&"$fd" 2>/dev/null)

	# Restore terminal and close fd
	stty -F /dev/tty "$old_stty" 2>/dev/null
	exec {fd}>&-

	# Debug: show hex dump of raw response
	_theme_debug "detect_terminal_theme: raw response hex='$(printf '%s' "$response" | od -A x -t x1z -v | head -3)'"

	# DA1 sentinel check: if response starts with \e[ instead of \e], terminal
	# doesn't support OSC 11 (DA1 arrived first)
	if [[ -z "$response" ]]; then
		_theme_debug "detect_terminal_theme: no response, marking OSC 11 unsupported"
		_OSC11_SUPPORTED="no"
		return 1
	fi

	if [[ "$response" == $'\033['* ]]; then
		_theme_debug "detect_terminal_theme: DA1 arrived first, marking OSC 11 unsupported"
		_OSC11_SUPPORTED="no"
		return 1
	fi

	# Extract color spec from OSC 11 response: \e]11;rgb:R/G/B
	# Strip everything from BEL or ST onward (DA1 response follows)
	local color_spec
	# Remove from BEL onward
	response="${response%%$'\007'*}"
	# Remove from ST (\e\) onward
	response="${response%%$'\033\\'*}"
	if [[ "$response" =~ $'\033']11\;(.*) ]]; then
		color_spec="${BASH_REMATCH[1]}"
	else
		_theme_debug "detect_terminal_theme: failed to parse response"
		return 1
	fi

	_theme_debug "detect_terminal_theme: color_spec='$color_spec'"

	# Parse rgb:R/G/B or rgba:R/G/B/A format (1-4 hex digits per channel)
	local r_hex g_hex b_hex
	if [[ "$color_spec" =~ ^rgba?:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+) ]]; then
		r_hex="${BASH_REMATCH[1]}"
		g_hex="${BASH_REMATCH[2]}"
		b_hex="${BASH_REMATCH[3]}"
	else
		_theme_debug "detect_terminal_theme: unrecognized color format '$color_spec'"
		return 1
	fi

	# Scale hex channels to 16-bit (0-65535) following terminal-colorsaurus:
	# value * 65535 / (16^len - 1)
	_scale_channel() {
		local hex="$1"
		local len=${#hex}
		local val=$((16#$hex))
		local max=$(( (1 << (len * 4)) - 1 ))
		echo $(( val * 65535 / max ))
	}

	local r g b
	r=$(_scale_channel "$r_hex")
	g=$(_scale_channel "$g_hex")
	b=$(_scale_channel "$b_hex")

	_theme_debug "detect_terminal_theme: RGB16=($r, $g, $b)"

	# Compute CIELAB perceived lightness using awk for floating point.
	# Steps (matching terminal-colorsaurus):
	#   1. Normalize to [0,1]
	#   2. sRGB gamma correction (linearize)
	#   3. CIE luminance: Y = 0.2126*R + 0.7152*G + 0.0722*B
	#   4. CIELAB L*: perceived lightness 0-100, normalized to 0-1
	local lightness
	lightness=$(awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN {
		# Normalize to [0,1]
		r = r / 65535; g = g / 65535; b = b / 65535;

		# sRGB gamma correction
		if (r <= 0.04045) r = r / 12.92; else r = ((r + 0.055) / 1.055) ^ 2.4;
		if (g <= 0.04045) g = g / 12.92; else g = ((g + 0.055) / 1.055) ^ 2.4;
		if (b <= 0.04045) b = b / 12.92; else b = ((b + 0.055) / 1.055) ^ 2.4;

		# CIE luminance
		Y = 0.2126 * r + 0.7152 * g + 0.0722 * b;

		# CIELAB perceived lightness (L* / 100)
		if (Y <= 216.0 / 24389.0)
			L = Y * (24389.0 / 27.0) / 100.0;
		else
			L = (Y ^ (1.0/3.0) * 116.0 - 16.0) / 100.0;

		printf "%.4f", L;
	}')

	_theme_debug "detect_terminal_theme: perceived_lightness=$lightness"

	# Threshold at 0.5 (perceptual midpoint)
	local result
	result=$(awk -v l="$lightness" 'BEGIN { print (l < 0.5) ? "dark" : "light" }')

	_theme_debug "detect_terminal_theme: result=$result"
	_OSC11_SUPPORTED="yes"
	echo "$result"
}

function set_system_color_theme() {
	local color_theme

	_theme_debug "set_system_color_theme: starting"

	if [[ -n "$TMUX" ]]; then
		# Inside tmux: read from tmux global environment (set by theme toggle
		# keybinding or mode 2031 hooks). OSC 11 responses are intercepted by
		# tmux and never reach the pane, so detection cannot work here.
		color_theme=$(tmux show-environment -g SYSTEM_COLOR_THEME 2>/dev/null | cut -d= -f2)
		_theme_debug "set_system_color_theme: from tmux env '$color_theme'"
	elif [[ "$TERM_PROGRAM" == "vscode" || "$TERM_PROGRAM" == "zed" ]]; then
		# VSCode and Zed embedded terminals don't support OSC 11 queries,
		# causing a full 1-second stty timeout on every prompt. Skip detection.
		_theme_debug "set_system_color_theme: skipping OSC 11 (unsupported terminal: TERM_PROGRAM=$TERM_PROGRAM)"
	else
		# Outside tmux: detect via OSC 11 query
		color_theme=$(detect_terminal_theme)
		_theme_debug "set_system_color_theme: detected '$color_theme'"
	fi

	# Default to dark if nothing worked
	[[ -z "$color_theme" ]] && color_theme="dark"

	_theme_debug "set_system_color_theme: final SYSTEM_COLOR_THEME='$color_theme'"
	export SYSTEM_COLOR_THEME=$color_theme
}

function set_custom_theme {
	if [ $SYSTEM_COLOR_THEME == 'dark' ]; then
		_theme_debug "set_custom_theme: applying dark theme (adwaita)"
		starship config palette adwaita
		export BAT_THEME='adwaita'
	else
		_theme_debug "set_custom_theme: applying light theme (rose-pine-dawn)"
		starship config palette rose-pine-dawn
		export BAT_THEME='rose-pine-dawn'
	fi
}

function refresh_terminal_theme() {
	[[ $- != *i* ]] && return

	_theme_debug "refresh_terminal_theme: refreshing"
	set_system_color_theme
	set_custom_theme
	_theme_debug "refresh_terminal_theme: done, SYSTEM_COLOR_THEME='$SYSTEM_COLOR_THEME'"
}

# Function to set the pane title to the command being run
function set_command_title() {
	[[ $- != *i* ]] && return

	# Ignore commands from starship, bash-preexec, and the PROMPT_COMMAND itself.
	# We use a case statement to match against the command string.
	case "$BASH_COMMAND" in
		*"starship_precmd"*)   return ;;
		*"__bp_trap_string"*)  return ;;
		"$PROMPT_COMMAND")     return ;;
		"trap - DEBUG")        return ;;
	esac

	# Extract the first word of the command.
	local first_word=${BASH_COMMAND%% *}

	# If the command wasn't ignored, set the first word as the pane title.
	printf "\033]2;%s\007" "$first_word" >/dev/tty
}

# Function to reset the pane title to a default value ("bash")
function reset_title() {
	[[ $- != *i* ]] && return

	printf "\033]2;bash\007" >/dev/tty
}

# Only set up interactive shell features if running interactively
if [[ $- == *i* ]]; then
	# # Before running a command, set the title to that command.
	trap 'set_command_title' DEBUG

	# Before displaying the prompt, reset the title to "bash".
	PROMPT_COMMAND="reset_title"

	if command -v starship &>/dev/null;  then
		export STARSHIP_CONFIG="$HOME/.config/starship/config.toml"
		eval "$(starship init bash)"

		# Before showing the prompt, set themes and reset title
		function precmd_user_func() {
			refresh_terminal_theme
		}

		starship_precmd_user_func="precmd_user_func"
	fi
fi
