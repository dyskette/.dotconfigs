if [ -d "$HOME/.local/opt/fnm" ]; then
    eval "$(fnm env --use-on-cd --shell bash)"
fi
