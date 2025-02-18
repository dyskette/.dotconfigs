if which gsettings &>/dev/null && [ "$(gsettings get org.gnome.desktop.interface color-scheme)" == \'prefer-dark\' ]; then
    export BAT_THEME=kanagawa-wave
else
    export BAT_THEME=kanagawa-lotus
fi
