if which gsettings &>/dev/null && [ "$(gsettings get org.gnome.desktop.interface color-scheme)" == \'prefer-dark\' ]; then
    export BAT_THEME=everforest
else
    export BAT_THEME=rose-pine-dawn
fi
