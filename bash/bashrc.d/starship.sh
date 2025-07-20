function set_system_color_theme() {
	color_theme='dark'
	if [ "$(systemd-detect-virt)" == "wsl" ]; then
		use_light_theme=`reg.exe Query "HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize" /v AppsUseLightTheme | awk '{if (match($0, 0x)) print substr($3, 3, 1)}'`

		if [ "$use_light_theme" == "0" ]; then
			color_theme='dark'
		else
			color_theme='light'
		fi

		unset use_light_theme
	else
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

if command -v starship &>/dev/null;  then
	export STARSHIP_CONFIG="$HOME/.config/starship/config.toml"
	eval "$(starship init bash)"

	# Before showing the prompt, set starship's palette based on the desktop theme
	function set_starship_palette() {
		set_system_color_theme

		if [ $SYSTEM_COLOR_THEME == 'dark' ]; then
			starship config palette kanagawa-wave
			export BAT_THEME='kanagawa-wave'
		else
			starship config palette rose-pine-dawn
			export BAT_THEME='rose-pine-dawn'
		fi
	}
	starship_precmd_user_func="set_starship_palette"
fi
