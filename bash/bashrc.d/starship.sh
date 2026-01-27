# Set DEBUG_THEME=1 to enable debug output
function _theme_debug() {
	[[ -n "$DEBUG_THEME" ]] && echo "[theme-debug] $*" >&2
}

# Detect terminal theme via OSC 11 escape sequence (works over SSH)
# Result is cached in _TERMINAL_THEME_CACHE to avoid repeated queries
# which can interfere with paste operations over SSH
function detect_terminal_theme() {
	# Return cached result if available
	if [[ -n "$_TERMINAL_THEME_CACHE" ]]; then
		_theme_debug "detect_terminal_theme: using cached value '$_TERMINAL_THEME_CACHE'"
		echo "$_TERMINAL_THEME_CACHE"
		return 0
	fi

	# Skip if no controlling terminal
	if [[ ! -e /dev/tty ]]; then
		_theme_debug "detect_terminal_theme: no /dev/tty, skipping"
		return 1
	fi

	local response old_stty
	# Use /dev/tty directly to avoid issues with command substitution
	old_stty=$(stty -g -F /dev/tty 2>/dev/null) || {
		_theme_debug "detect_terminal_theme: failed to save stty settings"
		return 1
	}
	stty -F /dev/tty raw -echo min 0 time 1 2>/dev/null || {
		_theme_debug "detect_terminal_theme: failed to set raw mode"
		return 1
	}

	# Send query and read response via /dev/tty
	printf '\e]11;?\a' > /dev/tty
	read -r -t 0.1 -d $'\a' response < /dev/tty 2>/dev/null

	stty -F /dev/tty "$old_stty" 2>/dev/null

	_theme_debug "detect_terminal_theme: raw response='$response'"

	if [[ "$response" =~ rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+) ]]; then
		local r=$((16#${BASH_REMATCH[1]:0:2}))
		local g=$((16#${BASH_REMATCH[2]:0:2}))
		local b=$((16#${BASH_REMATCH[3]:0:2}))
		# Calculate perceived luminance (ITU-R BT.709)
		local luminance=$(( (r * 299 + g * 587 + b * 114) / 1000 ))

		_theme_debug "detect_terminal_theme: RGB=($r, $g, $b) luminance=$luminance"

		if (( luminance > 128 )); then
			_theme_debug "detect_terminal_theme: detected 'light' (luminance > 128)"
			_TERMINAL_THEME_CACHE="light"
		else
			_theme_debug "detect_terminal_theme: detected 'dark' (luminance <= 128)"
			_TERMINAL_THEME_CACHE="dark"
		fi
		echo "$_TERMINAL_THEME_CACHE"
		return 0
	fi
	_theme_debug "detect_terminal_theme: failed to parse response, no rgb: pattern found"
	return 1
}

# Clear the terminal theme cache to force re-detection
function refresh_terminal_theme() {
	_theme_debug "refresh_terminal_theme: clearing cache"
	unset _TERMINAL_THEME_CACHE
	set_system_color_theme
	set_custom_theme
	_theme_debug "refresh_terminal_theme: done, SYSTEM_COLOR_THEME='$SYSTEM_COLOR_THEME'"
}

function set_system_color_theme() {
	local color_theme

	_theme_debug "set_system_color_theme: starting detection"

	# 1. Try terminal-level detection first (works over SSH)
	color_theme=$(detect_terminal_theme)

	# 2. Fall back to system-level detection
	if [[ -z "$color_theme" ]]; then
		_theme_debug "set_system_color_theme: terminal detection failed, trying system-level"
		color_theme='dark'

		# Check if we're in WSL
		if command -v systemd-detect-virt &>/dev/null && [ "$(systemd-detect-virt)" == "wsl" ]; then
			_theme_debug "set_system_color_theme: detected WSL environment"
			use_light_theme=`reg.exe Query "HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize" /v AppsUseLightTheme | awk '{if (match($0, 0x)) print substr($3, 3, 1)}'`
			_theme_debug "set_system_color_theme: WSL registry value='$use_light_theme'"

			if [ "$use_light_theme" == "0" ]; then
				color_theme='dark'
			else
				color_theme='light'
			fi

			unset use_light_theme
		# Check if we're on Windows (git bash) - detect by presence of reg.exe
		elif command -v reg.exe &>/dev/null; then
			_theme_debug "set_system_color_theme: detected Git Bash (Windows)"
			# Git bash requires MSYS_NO_PATHCONV to prevent path translation
			use_light_theme=$(MSYS_NO_PATHCONV=1 reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme 2>/dev/null | awk '{if (match($0, /0x/)) print substr($3, 3, 1)}')
			_theme_debug "set_system_color_theme: Git Bash registry value='$use_light_theme'"

			if [ "$use_light_theme" == "0" ]; then
				color_theme='dark'
			else
				color_theme='light'
			fi

			unset use_light_theme
		# Check if we're on Linux with GNOME
		elif command -v gsettings &>/dev/null; then
			_theme_debug "set_system_color_theme: detected GNOME (gsettings available)"
			color_scheme=`gsettings get org.gnome.desktop.interface color-scheme`
			_theme_debug "set_system_color_theme: gsettings color-scheme='$color_scheme'"

			if [ "$color_scheme" == \'prefer-dark\' ]; then
				color_theme='dark'
			else
				color_theme='light'
			fi

			unset color_scheme
		else
			_theme_debug "set_system_color_theme: no system detection method available, using default 'dark'"
		fi
	else
		_theme_debug "set_system_color_theme: terminal detection succeeded with '$color_theme'"
	fi

	_theme_debug "set_system_color_theme: final SYSTEM_COLOR_THEME='$color_theme'"
	export SYSTEM_COLOR_THEME=$color_theme
}

function set_custom_theme {
	if [ $SYSTEM_COLOR_THEME == 'dark' ]; then
		_theme_debug "set_custom_theme: applying dark theme (gruvbox)"
		starship config palette gruvbox
		export BAT_THEME='gruvbox'
	else
		_theme_debug "set_custom_theme: applying light theme (rose-pine-dawn)"
		starship config palette rose-pine-dawn
		export BAT_THEME='rose-pine-dawn'
	fi
}

# Function to set the pane title to the command being run
function set_command_title() {
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
  printf "\033]2;%s\007" "$first_word"
}

# Function to reset the pane title to a default value ("bash")
function reset_title() {
  printf "\033]2;bash\007"
}

# Only set up interactive shell features if running interactively
if [[ $- == *i* ]]; then
	# Before running a command, set the title to that command.
	trap 'set_command_title' DEBUG

	# Before displaying the prompt, reset the title to "bash".
	PROMPT_COMMAND="reset_title"

	if command -v starship &>/dev/null;  then
		export STARSHIP_CONFIG="$HOME/.config/starship/config.toml"
		eval "$(starship init bash)"

		# Before showing the prompt, set themes and reset title
		function precmd_user_func() {
			set_system_color_theme
			set_custom_theme
		}

		starship_precmd_user_func="precmd_user_func"
	fi
fi
