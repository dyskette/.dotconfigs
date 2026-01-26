function set_system_color_theme() {
	color_theme='dark'

	# Check if we're in WSL
	if command -v systemd-detect-virt &>/dev/null && [ "$(systemd-detect-virt)" == "wsl" ]; then
		use_light_theme=`reg.exe Query "HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize" /v AppsUseLightTheme | awk '{if (match($0, 0x)) print substr($3, 3, 1)}'`

		if [ "$use_light_theme" == "0" ]; then
			color_theme='dark'
		else
			color_theme='light'
		fi

		unset use_light_theme
	# Check if we're on Windows (git bash) - detect by presence of reg.exe
	elif command -v reg.exe &>/dev/null; then
		# Git bash requires MSYS_NO_PATHCONV to prevent path translation
		use_light_theme=$(MSYS_NO_PATHCONV=1 reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme 2>/dev/null | awk '{if (match($0, /0x/)) print substr($3, 3, 1)}')

		if [ "$use_light_theme" == "0" ]; then
			color_theme='dark'
		else
			color_theme='light'
		fi

		unset use_light_theme
	# Check if we're on Linux with GNOME
	elif command -v gsettings &>/dev/null; then
		color_scheme=`gsettings get org.gnome.desktop.interface color-scheme`

		if [ "$color_scheme" == \'prefer-dark\' ]; then
			color_theme='dark'
		else
			color_theme='light'
		fi

		unset color_scheme
	fi

	export SYSTEM_COLOR_THEME=$color_theme
	unset color_theme
}

function set_custom_theme {
	if [ $SYSTEM_COLOR_THEME == 'dark' ]; then
		starship config palette gruvbox
		export BAT_THEME='gruvbox'
	else
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
