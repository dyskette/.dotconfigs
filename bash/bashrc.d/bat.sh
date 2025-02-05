if which gsettings &>/dev/null && [ "$(gsettings get org.gnome.desktop.interface color-scheme)" == \'prefer-dark\' ]; then
    export BAT_THEME=ayu-dark
else
    export BAT_THEME=ayu-light
fi
