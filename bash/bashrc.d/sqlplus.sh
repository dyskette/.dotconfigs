if [ -d "$HOME/.local/opt/oracle" ]; then
    INSTANTCLIENT_DIR=$(find "$HOME/.local/opt/oracle" -maxdepth 1 -type d -name 'instantclient_*' 2>/dev/null | head -n 1)
    if [ -n "$INSTANTCLIENT_DIR" ]; then
        export LD_LIBRARY_PATH="$INSTANTCLIENT_DIR:$LD_LIBRARY_PATH"
    fi
    unset INSTANTCLIENT_DIR
fi
