# Light or dark, for the tools that cannot ask the terminal themselves.
#
# bat and delta choose their theme by asking the terminal for its background
# colour (OSC 11). That works when they own the terminal and only then: inside
# an fzf preview, lazygit or any other pipeline, a program is already reading
# the terminal in raw mode and takes the reply. bat then waits a full second
# for an answer that never arrives, falls back to its built-in Monokai theme,
# paints the query itself (]10;? ]11;?) over the preview, and the terminal's
# reply lands in fzf's input as keystrokes, which empties the preview.
#
# So the question is asked once, here, where this shell is the one holding the
# terminal, and the answer is handed on through the environment:
#
#   SYSTEM_COLOR_THEME   light|dark, the name the PowerShell profile already
#                        sets from the Windows registry, so files.sh can write
#                        one preview command for both platforms
#   BAT_THEME            read by bat and by delta (for its syntax colours),
#                        and it wins over --theme in bat/config
#
# Detection runs at startup only, so switching the system theme does not reach
# shells that are already open:
#
#   theme              re-detect
#   theme light|dark   force one
#
# Loaded before files.sh and fzf.sh (alphabetical order), so anything there may
# read SYSTEM_COLOR_THEME while being sourced.

__theme_dark='everforest-dark-medium'
__theme_light='everforest-light-medium'

# Ask the terminal for its background colour and echo 'light' or 'dark'.
# Fails when there is no terminal, or it does not answer.
__theme_from_terminal() {
  local saved reply i hex c=()

  # Every </dev/tty below fails outright when the shell has no controlling
  # terminal (cron, a pipeline in a script), and bash reports the failed
  # redirection itself, so stderr is dropped for the whole function.
  saved=$(stty -g </dev/tty) || return 1

  # min 0 time 2: read() gives up after 200 ms, so a terminal that ignores the
  # query costs that much once instead of hanging the shell.
  stty raw -echo min 0 time 2 </dev/tty || return 1
  printf '\e]11;?\a' >/dev/tty
  # Terminals end the reply with BEL or with ST (ESC \), mirroring the query.
  # On an ST reply the BEL never comes, but -t keeps what did arrive, so it
  # still parses -- only after the timeout.
  IFS= read -r -t 0.3 -d $'\a' reply </dev/tty
  stty "$saved" </dev/tty

  # rgb:RRRR/GGGG/BBBB, or two digits per channel on older terminals.
  [[ "$reply" =~ rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+) ]] || return 1
  for i in 1 2 3; do
    # The high byte of each channel, whatever width it was reported in.
    hex="${BASH_REMATCH[i]}00"
    c+=("$((16#${hex:0:2}))")
  done

  # Rec. 709 luma; half of full scale is the usual light/dark cut.
  if (((2126 * c[0] + 7152 * c[1] + 722 * c[2]) / 10000 > 127)); then
    echo light
  else
    echo dark
  fi
} 2>/dev/null

# The desktop's own setting, for terminals that do not answer OSC 11.
__theme_from_desktop() {
  local scheme
  command -v gsettings &>/dev/null || return 1
  scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null) || return 1
  case "$scheme" in
    *prefer-light*) echo light ;;
    *prefer-dark*)  echo dark ;;
    *)              return 1 ;;
  esac
}

# theme [light|dark]: set the colour scheme for this shell and everything it
# starts. With no argument, ask the terminal again.
theme() {
  local scheme="$1"

  case "$scheme" in
    light | dark) ;;
    "")
      # COLORFGBG is set by terminals that predate OSC 11 (fg;bg, sometimes
      # fg;default;bg); background 7 or 15 is a light palette.
      scheme=$(__theme_from_terminal) ||
        case "${COLORFGBG##*;}" in
          7 | 15) scheme=light ;;
          ?*)     scheme=dark ;;
          *)      scheme=$(__theme_from_desktop) || scheme=dark ;;
        esac
      ;;
    *)
      echo "theme: expected 'light', 'dark' or no argument" >&2
      return 2
      ;;
  esac

  export SYSTEM_COLOR_THEME="$scheme"
  if [[ "$scheme" == light ]]; then
    export BAT_THEME="$__theme_light"
  else
    export BAT_THEME="$__theme_dark"
  fi
}

# A nested shell (nvim's terminal, a subshell) inherits the answer instead of
# asking again; a new terminal window starts without it and asks for itself.
# A tmux or zellij pane inherits what the server was started with, which is the
# one case that can go stale -- `theme` fixes it.
if [[ $- == *i* && -z "$SYSTEM_COLOR_THEME" ]]; then
  theme
fi
