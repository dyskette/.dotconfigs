if which gsettings &>/dev/null && [ "$(gsettings get org.gnome.desktop.interface color-scheme)" == \'prefer-dark\' ]; then
    export BAT_THEME=everforest
else
    export BAT_THEME=rose-pine-dawn
fi

# Not working yet: https://github.com/sharkdp/bat/pull/3168
export BAT_THEME_DARK="everforest"
export BAT_THEME_LIGHT="rose-pine-dawn"
