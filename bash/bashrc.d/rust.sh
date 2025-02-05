CARGO_ENV_PATH="$HOME/.cargo/env"
if [ -f "$CARGO_ENV_PATH" ]; then
	. "$CARGO_ENV_PATH"
fi
unset CARGO_ENV_PATH
