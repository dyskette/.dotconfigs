if which starship &>/dev/null; then
    export STARSHIP_CONFIG="$HOME/.bashrc.d/starship.toml"
    eval "$(starship init bash)"

	# Before showing the prompt, set starship's palette based on the desktop theme
    function set_starship_palette(){
        if which gsettings &>/dev/null && [ "$(gsettings get org.gnome.desktop.interface color-scheme)" == \'prefer-dark\' ]; then
            starship config palette ayu_dark
        else
            starship config palette ayu_light
        fi
    }
    starship_precmd_user_func="set_starship_palette"
fi
