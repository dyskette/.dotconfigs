if [ -d "$HOME/.local/opt/go" ]; then
    export GOPATH="$HOME/.local/opt/go-packages"
    export PATH="$GOPATH/bin:$PATH"
fi
