if command -v starship &>/dev/null;  then
    export STARSHIP_CONFIG="$HOME/.config/starship/config.toml"
    eval "$(starship init bash)"

	# Before showing the prompt, set starship's palette based on the desktop theme
    function set_starship_palette(){
        if which gsettings &>/dev/null && [ "$(gsettings get org.gnome.desktop.interface color-scheme)" == \'prefer-dark\' ]; then
            starship config palette everforest
        else
            starship config palette rose-pine-dawn
        fi
    }
    starship_precmd_user_func="set_starship_palette"
fi
